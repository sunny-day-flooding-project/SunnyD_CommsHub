#!/usr/bin/env python3
"""
Bluetooth LE automated connections (updated)
Uses bleak to detect devices and launches configured external tool (for example ble-serial).
Improved robustness:
 - per-device asyncio locks to avoid concurrent launches for the same address
 - serialized scanner stop/start with a global lock
 - guaranteed scanner restart in finally blocks
 - bounded subprocess timeout and safe-kill on hang
 - optional soft HCI reset (btmgmt or hciconfig) on scanner/start failures or non-zero child exit
 - better signal handling for clean shutdown
Configure devices in autoconnect.ini as before (as shown in ble-serial project).
"""
import asyncio
import logging
import argparse
import configparser
import signal
import subprocess
import shlex
import sys
import os
from bleak import BleakScanner
from bleak.backends.device import BLEDevice


# ---------- Configuration and CLI ----------
parser = argparse.ArgumentParser(
    formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    description='Service to automatically connect with devices that get available.'
)
parser.add_argument('-c', '--config', default='autoconnect.ini', required=False,
                    help='Path to a INI file with device configs')
parser.add_argument('-v', '--verbose', dest='verbose', action='store_true',
                    help='Increase log level from info to debug')
parser.add_argument('-m', '--min-rssi', dest='min_rssi', default=-127, type=int,
                    help='Ignore devices with weaker signal strength')
parser.add_argument('-t', '--timeout', dest='timeout', default=10, type=int,
                    help='Pause scan (seconds) to let tool start')
parser.add_argument('--child-timeout', dest='child_timeout', default=3600, type=int,
                    help='Max runtime (seconds) for the launched tool before being killed')
args = parser.parse_args()


# Note about logging, there is a tremendous amount of logging available
# if everything is set to DEBUG (too much to normally read)
#
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('[AUTOCONNECT] %(asctime)s | %(levelname)s | %(name)s | %(message)s'))

root = logging.getLogger()
root.handlers = []            # drop default handlers
root.addHandler(handler)

if args.verbose:
    # Root DEBUG so module's logging.debug() calls are emitted
    root.setLevel(logging.DEBUG)
    # Silence noisy third-party modules to INFO or WARNING
    logging.getLogger("bleak").setLevel(logging.INFO)
    logging.getLogger("dbus_next").setLevel(logging.WARNING)
    logging.getLogger("asyncio").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
else:
    root.setLevel(logging.INFO)


# ---------- Globals ----------
config = configparser.ConfigParser(allow_no_value=True)
if not os.path.exists(args.config):
    logging.error("Config file %s not found", args.config)
    sys.exit(1)
with open(args.config, 'r') as f:
    config.read_file(f)

# Bleak scanner - will be created in main
scanner: BleakScanner = None

# Locks and state
global_scan_lock = asyncio.Lock()       # serialize stop/start of the scanner
per_device_locks = {}                   # address -> asyncio.Lock()
shutdown_event = asyncio.Event()


# ---------- Utility functions ----------
async def run_soft_hci_reset():
    logging.info("Attempting soft HCI reset (hciconfig reset preferred)")

    # 1) Try quick hciconfig reset (fast; may not exist on some systems)
    try:
        p = await asyncio.create_subprocess_exec('sudo', '/usr/bin/hciconfig', 'hci0', 'reset',
                                                 stdout=asyncio.subprocess.PIPE,
                                                 stderr=asyncio.subprocess.PIPE)
        try:
            out, err = await asyncio.wait_for(p.communicate(), timeout=5)
        except asyncio.TimeoutError:
            logging.warning("hciconfig reset timed out")
            p.kill()
            await p.wait()
            out, err = b'', b'timeout'
        if p.returncode == 0:
            logging.info("hciconfig reset succeeded")
            await asyncio.sleep(0.5)
            return True
        logging.debug("hciconfig reset rc=%s stdout=%s stderr=%s", p.returncode,
                      out.decode(errors='ignore')[:300], err.decode(errors='ignore')[:300])
    except FileNotFoundError:
        logging.debug("hciconfig not found; skipping")
    except Exception:
        logging.exception("hciconfig reset raised")

    # 2) Fall back to btmgmt power off/on sequence (each run with its own timeout)
    cmd_off = ['sudo', 'btmgmt', '-i', 'hci0', 'power', 'off']
    cmd_on  = ['sudo', 'btmgmt', '-i', 'hci0', 'power', 'on']

    # power off
    try:
        p_off = await asyncio.create_subprocess_exec(*cmd_off,
                                                     stdout=asyncio.subprocess.PIPE,
                                                     stderr=asyncio.subprocess.PIPE)
        try:
            out_off, err_off = await asyncio.wait_for(p_off.communicate(), timeout=5)
        except asyncio.TimeoutError:
            logging.warning("btmgmt power off timed out; killing")
            p_off.kill()
            await p_off.wait()
            out_off, err_off = b'', b'timeout'
        logging.debug("btmgmt off rc=%s stdout=%s stderr=%s", p_off.returncode,
                      out_off.decode(errors='ignore')[:400], err_off.decode(errors='ignore')[:400])
    except FileNotFoundError:
        logging.error("btmgmt not present on system; cannot soft reset")
        return False
    except Exception:
        logging.exception("btmgmt power off failed")
        return False

    # small settle
    await asyncio.sleep(0.6)

    # power on
    try:
        p_on = await asyncio.create_subprocess_exec(*cmd_on,
                                                    stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.PIPE)
        try:
            out_on, err_on = await asyncio.wait_for(p_on.communicate(), timeout=6)
        except asyncio.TimeoutError:
            logging.warning("btmgmt power on timed out; killing")
            p_on.kill()
            await p_on.wait()
            out_on, err_on = b'', b'timeout'
        logging.debug("btmgmt on rc=%s stdout=%s stderr=%s", p_on.returncode,
                      out_on.decode(errors='ignore')[:400], err_on.decode(errors='ignore')[:400])

        if p_on.returncode == 0:
            logging.info("btmgmt power on succeeded")
            await asyncio.sleep(0.6)
            return True
        else:
            logging.warning("btmgmt power on returned non-zero")
            return False
    except Exception:
        logging.exception("btmgmt power on failed")
        return False

async def safe_scanner_stop():
    """Stop the bleak scanner, with a fallback soft reset if stop fails."""
    try:
        await scanner.stop()
        logging.debug("scanner.stop() succeeded")
        return True
    except Exception as e:
        logging.exception("scanner.stop() failed: %s", e)
        # try a soft reset and consider that the fallback
        await run_soft_hci_reset()
        # attempt to continue; caller may choose to restart scanner
        return False

async def safe_scanner_start():
    """Start the bleak scanner, with soft-reset fallback if start fails."""
    try:
        await scanner.start()
        logging.debug("scanner.start() succeeded")
        return True
    except Exception as e:
        logging.exception("scanner.start() failed: %s", e)
        # try soft reset then try start again
        ok = await run_soft_hci_reset()
        if ok:
            try:
                await asyncio.sleep(0.5)
                await scanner.start()
                logging.info("scanner.start() succeeded after soft reset")
                return True
            except Exception as e2:
                logging.exception("scanner.start() still failed after soft reset: %s", e2)
        return False

def create_or_get_lock(addr: str) -> asyncio.Lock:
    lock = per_device_locks.get(addr)
    if lock is None:
        lock = asyncio.Lock()
        per_device_locks[addr] = lock
    return lock


# ---------- Core runner ----------
async def run_tool(conf_section: dict, lock_id: str):
    """Run the configured tool for the device lock_id with robust scanner handling."""
    # ignore unknown config entries defensively
    executable = conf_section.get('executable')
    if not executable:
        logging.error("No 'executable' configured for device %s", lock_id)
        return

    lock = create_or_get_lock(lock_id)
    if lock.locked():
        logging.debug("Device %s already has an active run; ignoring", lock_id)
        return

    async with lock:
        logging.info("Preparing to run tool for %s", lock_id)
        # Stop scanner under global lock so no overlapping stop/start operations occur
        async with global_scan_lock:
            logging.debug("Acquired global scan lock to stop scanner")
            await safe_scanner_stop()
            # give BlueZ a small settle time for resource cleanup
            await asyncio.sleep(0.75)

        # Build params: keep same semantics as original script
        params = [executable]
        for key, val in conf_section.items():
            if key == 'executable':
                continue
            params.append(f'--{key}')
            if val:
                params.append(val)
        logging.info("Exec: %s", params)

        proc = None
        rc = None
        try:
            proc = await asyncio.create_subprocess_exec(*params,
                                                        stdin=asyncio.subprocess.DEVNULL,
                                                        stdout=None,
                                                        stderr=None)

            try:
                # wait for process exit with a timeout
                await asyncio.wait_for(proc.wait(), timeout=args.child_timeout)
            except asyncio.TimeoutError:
                logging.warning("Launched tool timed out after %ds; killing", args.child_timeout)
                try:
                    proc.kill()
                except Exception:
                    logging.exception("Failed to kill timed-out child process")
                try:
                    await asyncio.wait_for(proc.wait(), timeout=5)
                except asyncio.TimeoutError:
                    logging.error("Timed-out waiting for child to die after kill")
            finally:
                rc = proc.returncode if proc else None
                logging.info("Tool finished for %s with return code %s", lock_id, rc)

        finally:
            # if child returned non-zero, attempt a soft HCI reset to clear leaked state
            if rc is None:
                # if process creation failed, attempt reset as well
                logging.warning("Child didn't start properly; attempting soft HCI reset")
                try:
                    await run_soft_hci_reset()
                except Exception:
                    logging.exception("run_soft_hci_reset() raised")
            elif rc != 0:
                logging.warning("Child exited with non-zero; attempting soft HCI reset")
                try:
                    await run_soft_hci_reset()
                except Exception:
                    logging.exception("run_soft_hci_reset() raised")

            # small settle before restarting the scanner
            await asyncio.sleep(0.8)

            # Ensure scanner is restarted; do this under the global lock too
            async with global_scan_lock:
                logging.debug("Acquired global scan lock to restart scanner")
                started = await safe_scanner_start()
                if not started:
                    logging.error("Failed to restart scanner after handling child; scanner may be non-functional")

# ---------- Detection callback ----------
def detection_callback(device: BLEDevice, adv_data):
    logging.debug(f'{device.address} = {adv_data.local_name} (RSSI: {adv_data.rssi}) Services={adv_data.service_uuids}')
    try:
        if device.address in config:
            section = config[device.address]
            logging.debug("Found configured device %s (RSSI=%s)", device.address, adv_data.rssi)
            if int(adv_data.rssi) <= args.min_rssi:
                logging.debug("Ignoring device %s because RSSI %s below threshold %s", device.address, adv_data.rssi, args.min_rssi)
                return
            # queue a task to handle the device (do not await here)
            asyncio.create_task(run_tool(section, device.address))
#        else:
#            logging.debug("Unknown device seen: %s (RSSI=%s)", device.address, adv_data.rssi)
    except Exception:
        logging.exception("Exception in detection_callback")


# ---------- Signal handling ----------
def handle_signal(sig_num, frame):
    logging.info("Signal %s received, initiating shutdown", sig_num)
    # set the shutdown event so main loop can exit cleanly
    try:
        # run in main thread loop
        loop = asyncio.get_event_loop()
        loop.call_soon_threadsafe(shutdown_event.set)
    except Exception:
        logging.exception("Failed to set shutdown event from signal handler")


# ---------- Main async entry ----------
async def main():
    global scanner
    # create scanner with callback
    scanner = BleakScanner(detection_callback)

    # hook signals for graceful shutdown
    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    # start scanner
    try:
        ok = await safe_scanner_start()
        if not ok:
            logging.error("Initial scanner start failed; trying soft HCI reset and one more start")
            await run_soft_hci_reset()
            await asyncio.sleep(0.5)
            if not await safe_scanner_start():
                logging.critical("Unable to start scanner; exiting")
                return
    except Exception:
        logging.exception("Exception during initial scanner start")
        return

    logging.info("Scanner started; monitoring for configured devices")

    # wait until shutdown_event is set
    await shutdown_event.wait()

    logging.info("Shutdown event set: stopping scanner and cleaning up")
    try:
        async with global_scan_lock:
            await safe_scanner_stop()
    except Exception:
        logging.exception("Exception while stopping scanner at shutdown")


# ---------- Script entry ----------
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info("KeyboardInterrupt received, exiting")
    except Exception:
        logging.exception("Unhandled exception in main; exiting")
    finally:
        logging.info("autoconnect exiting")
        