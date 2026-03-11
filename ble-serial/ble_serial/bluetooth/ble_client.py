# -*- coding: utf-8 -*-
"""
ble_client.py — robust discovery for Bleak on Raspberry Pi OS (BlueZ)

What’s new vs your last version:
  * Do GATT service discovery immediately in connect() with retries/backoff.
  * If discovery fails (e.g., link flaps), connect() returns False and the
    caller can retry cleanly (no partial setup).
  * Disconnected callback is debounced: it does NOT stop loops while the client
    is still initializing (pre-read/write setup).
  * setup_chars() assumes services already discovered, but can try once more
    if needed (defensive).
"""

from bleak import BleakClient, BleakScanner
from bleak.backends.characteristic import BleakGATTCharacteristic
from ble_serial.bluetooth.constants import ble_chars
from ble_serial.bluetooth.interface import BLE_interface
import logging
import asyncio
import time
import random
from typing import Optional, List, Iterable, Any

CONNECT_TIMEOUT = 15.0
DISCOVERY_TIMEOUT = 15.0
MAX_DISCOVERY_ATTEMPTS = 4
MAX_CONNECT_ATTEMPTS = 4
BASE_BACKOFF = 0.5
MAX_BACKOFF = 3.0

class BLE_client(BLE_interface):
    def __init__(self, adapter: str, id: str = None):
        self._send_queue = asyncio.Queue()
        self.adapter = adapter

        # State
        self.read_enabled = False
        self.write_enabled = False
        self.write_response_required = False
        self.dev: Optional[BleakClient] = None

        # Setup state flags
        self._initializing = False  # True from connect() start until setup_chars() finishes
        self._ready = False         # True after notifications (read path) are configured

    # ------------- Helpers -------------

    def _is_connected(self) -> bool:
        """Handle Bleak is_connected API as property or method."""
        if self.dev is None:
            return False
        ic = getattr(self.dev, "is_connected", False)
        try:
            return ic() if callable(ic) else bool(ic)
        except Exception:
            return False

    def _backoff(self, attempt: int) -> float:
        return min(MAX_BACKOFF, BASE_BACKOFF * (2 ** attempt) + random.uniform(0.0, 0.25))

    async def _discover_services_once(self) -> Any:
        """
        Try exactly once to perform discovery using:
          - client.get_services() if available
          - otherwise Linux backend: client._backend._get_services()
        Returns the services object on success; raises on failure.
        """
        # If already populated, return quickly
        services = getattr(self.dev, "services", None)
        if services is not None:
            return services

        # Preferred modern API (present on some platforms)
        get_services = getattr(self.dev, "get_services", None)
        if callable(get_services):
            return await asyncio.wait_for(get_services(), timeout=DISCOVERY_TIMEOUT)

        # Linux / BlueZ backend path
        backend = getattr(self.dev, "_backend", None)
        if backend is None or not hasattr(backend, "_get_services"):
            raise RuntimeError("Bleak backend does not expose _get_services() on this platform")

        await asyncio.wait_for(backend._get_services(), timeout=DISCOVERY_TIMEOUT)
        services = getattr(self.dev, "services", None)
        if services is None:
            raise RuntimeError("Service discovery did not populate services")
        return services

    async def _discover_services_with_retries(self) -> Optional[Any]:
        """
        Retry discovery a few times with backoff. If the device disconnects
        during discovery, return None so caller can treat it as a connect failure.
        """
        for attempt in range(MAX_DISCOVERY_ATTEMPTS):
            if not self._is_connected():
                return None
            try:
                return await self._discover_services_once()
            except asyncio.TimeoutError as e:
                logging.debug(f"Discovery timeout (attempt {attempt+1}): {e}")
            except Exception as e:
                # If the link dropped, abort early
                if not self._is_connected() or "Not connected" in str(e):
                    return None
                logging.debug(f"Discovery error (attempt {attempt+1}): {e}")
            await asyncio.sleep(self._backoff(attempt))
        return None

    def _iter_services(self, services_obj: Any) -> Iterable:
        """Yield service objects across Bleak variants."""
        if services_obj is None:
            return []
        if hasattr(services_obj, "services") and isinstance(getattr(services_obj, "services", None), dict):
            return services_obj.services.values()
        return services_obj

    # ------------- Public API -------------
    async def _connect_once(self, addr_str: str, addr_type: str, service_uuid: str, timeout: float) -> bool:
        """
        Single connection attempt:
          * scan
          * connect
          * discover services
        Returns True on success, False on any failure.
        """
        self._initializing = True
        self._ready = False

        scan_args = dict(adapter=self.adapter)
        if service_uuid:
            scan_args['service_uuids'] = [service_uuid]

        if addr_str:
            device = await BleakScanner.find_device_by_address(addr_str, timeout=timeout, **scan_args)
        else:
            logging.warning(
                'Picking first device with matching service, '
                'consider passing a specific device address, especially if there could be multiple devices'
            )
            device = await BleakScanner.find_device_by_filter(lambda dev, ad: True, timeout=timeout, **scan_args)

        assert device, 'No matching device found!'

        self.dev = BleakClient(
            device,
            address_type=addr_type,
            timeout=timeout or CONNECT_TIMEOUT,
            disconnected_callback=self.handle_disconnect
        )

        logging.info(f'Trying to connect with {device}')

        try:
            await asyncio.wait_for(self.dev.connect(), timeout=timeout or CONNECT_TIMEOUT)
        except asyncio.CancelledError:
            logging.warning("BLE connection attempt was cancelled by BlueZ/Bleak")
            self._initializing = False
            return False
        except Exception as e:
            logging.error(f"BLE connection failed: {e}")
            self._initializing = False
            return False

        if not self._is_connected():
            logging.error("BLE connection failed: connected returned but is_connected() is False")
            self._initializing = False
            return False

        # Give BlueZ a brief moment to settle (helps in fringe RF conditions)
        await asyncio.sleep(0.2)

        # ---- Perform discovery with retries BEFORE returning success ----
        services = await self._discover_services_with_retries()
        if services is None:
            logging.error("BLE connection failed: failed to discover services, device disconnected")
            self._initializing = False
            return False

        logging.info(f'Device {self.dev.address} connected and services discovered')
        self._initializing = False
        return True

    async def connect(self, addr_str: str, addr_type: str, service_uuid: str, timeout: float):
        """
        Retry-aware connect wrapper around _connect_once().
        Performs a few attempts with backoff and clean disconnects between tries.
        """
        for attempt in range(MAX_CONNECT_ATTEMPTS):
            ok = await self._connect_once(addr_str, addr_type, service_uuid, timeout)
            if ok:
                return True

            logging.warning(f"BLE connect attempt {attempt+1}/{MAX_CONNECT_ATTEMPTS} failed")

            # Clean up before retrying
            await self.disconnect()

            # Backoff before next attempt
            if attempt < MAX_CONNECT_ATTEMPTS - 1:
                delay = self._backoff(attempt)
                logging.info(f"Retrying BLE connection in {delay:.1f}s")
                await asyncio.sleep(delay)

        logging.error("BLE connection failed after maximum retry attempts")
        return False
    
    async def setup_chars(self, write_uuid: str, read_uuid: str, mode: str, write_response_required: bool):
        """
        Resolve requested characteristics and enable notifications (read path).
        Discovery should already be done in connect(). We keep a defensive fallback.
        """
        self.read_enabled = 'r' in mode
        self.write_enabled = 'w' in mode

        # Defensive: if services somehow missing, try once to discover
        services = getattr(self.dev, "services", None)
        if services is None:
            services = await self._discover_services_with_retries()
            if services is None:
                raise RuntimeError("Service discovery unavailable during setup (device may have disconnected)")

        if self.write_enabled:
            self.write_response_required = write_response_required
            write_cap = ['write'] if write_response_required else ['write-without-response']
            self.write_char = self.find_char(services, write_uuid, write_cap)
        else:
            logging.info('Writing disabled, skipping write UUID detection')

        if self.read_enabled:
            self.read_char = self.find_char(services, read_uuid, ['notify', 'indicate'])
            try:
                await self.dev.start_notify(self.read_char, self.handle_notify)
            except Exception as e:
                # Common BlueZ races:
                #   * EOFError when device disconnects mid-setup
                #   * org.bluez.Error.NotPermitted when notify already active
                logging.error(f"Failed to start notifications: {e}")
                await self.disconnect()
                return False
        else:
            logging.info('Reading disabled, skipping read UUID detection')

        # Mark ready only after I/O paths are armed
        self._ready = True
        return True

    def find_char(self, services, uuid: Optional[str], req_props: List[str]) -> BleakGATTCharacteristic:
        name = req_props[0]

        # Use user supplied UUID first, otherwise try included list
        if uuid:
            uuid_candidates = [uuid.lower()]
        else:
            uuid_candidates = [u.lower() for u in ble_chars]
            logging.debug(f'No {name} uuid specified, trying builtin list')

        results = []
        for srv in self._iter_services(services):
            for c in srv.characteristics:
                try:
                    cu = c.uuid.lower()
                except Exception:
                    cu = c.uuid
                if cu in uuid_candidates:
                    results.append(c)

        if uuid:
            assert len(results) > 0, f"No characteristic with specified {name} UUID {uuid} found!"
        else:
            assert len(results) > 0, (
                f"""No characteristic in builtin {name} list {uuid_candidates} found!

                    Please specify one with {'-w/--write-uuid' if name == 'write' else '-r/--read-uuid'}, see also --help"""
            )

        res_str = '\n'.join(f'\t{c} {c.properties}' for c in results)
        logging.debug(f'Characteristic candidates for {name}: \n{res_str}')

        # Check if there is an intersection of permission flags
        results[:] = [c for c in results if set(c.properties) & set(req_props)]

        assert len(results) > 0, f"No characteristic with {req_props} property found!"
        assert len(results) == 1, f"Multiple matching {name} characteristics found, please specify one"

        found = results[0]
        logging.info(f'Found {name} characteristic {found.uuid} (H. {found.handle})')
        return found

    def set_receiver(self, callback):
        self._cb = callback
        logging.info('Receiver set up')

    async def send_loop(self):
        assert hasattr(self, '_cb'), 'Callback must be set before receive loop!'
        while True:
            data = await self._send_queue.get()
            if data is None:
                break  # Let future end on shutdown
            if not self.write_enabled:
                logging.warning(f'Ignoring unexpected write data: {data}')
                continue
            logging.debug(f'Sending {data}')
            await self.dev.write_gatt_char(self.write_char, data, self.write_response_required)

    async def check_loop(self):
        while True:
            await asyncio.sleep(1)

    def stop_loop(self):
        logging.info('Stopping Bluetooth event loop')
        self._send_queue.put_nowait(None)

    async def disconnect(self):
        """
        Robust disconnect:
          * Stops notifications if active
          * Disconnects only once
          * Swallows all BlueZ/Bleak races
          * Resets internal state flags
        """
        try:
            dev = self.dev                      # Prevent repeated disconnect attempts during flapping
            if dev is None:
                return
            self._initializing = False          # Reset state flags so callbacks behave correctly
            self._ready = False
            if self.read_enabled and hasattr(self, "read_char"):    # Stop notifications if they were enabled
                try:
                    await dev.stop_notify(self.read_char)
                except Exception:
                    pass
            try:                                # Attempt disconnect
                if self._is_connected():
                    await dev.disconnect()
            except Exception:
                pass
        finally:                                # Ensure we never leave stale client objects around
            self.dev = None
            logging.info("Bluetooth disconnected")
        
    def queue_send(self, data: bytes):
        self._send_queue.put_nowait(data)

    def handle_notify(self, handle: int, data: bytes):
        logging.debug(f'Received notify from {handle}: {data}')
        if not self.read_enabled:
            logging.warning(f'Read unexpected data, dropping: {data}')
            return
        self._cb(data)

    def handle_disconnect(self, client: BleakClient):
        # If we disconnect during setup, let connect/setup fail naturally.
        if not self._ready:
            logging.warning(f'Device {client.address} disconnected (during setup)')
            return
        logging.warning(f'Device {client.address} disconnected')
        self.stop_loop()