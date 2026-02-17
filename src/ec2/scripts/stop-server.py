"""
Minecraft Server Stop Script
This script connects to a Minecraft server to monitor player count and then stops the server and ec2 instance when no players are online in a given period of time.

Please refer to docs found here for Protocol details:
    - https://minecraft.wiki/w/Java_Edition_protocol/Packets
    - https://minecraft.wiki/w/Java_Edition_protocol/Server_List_Ping
    - https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
"""

import asyncio
from dataclasses import dataclass
import json
import os
import random
import struct
import subprocess
import psutil

PLAYER_CHECK_INTERVAL = int(os.getenv("PLAYER_CHECK_INTERVAL", "180"))
SERVER_PID = int(os.getenv("SERVER_PID", "-1"))
INSTANCE_ID = os.getenv("INSTANCE_ID", "i-0123456789abcdef0")
RCON_SECRET = os.getenv("RCON_SECRET")
RCON_PORT = int(os.getenv("RCON_PORT", "-1"))


# Constants for VarInt encoding/decoding
SEGMENT_BITS = b'\x7F'[0] 
CONTINUE_BIT = b'\x80'[0]


def encode_varint(value: int) -> bytes:
    """
    Encodes an integer into minecrafts VarInt format.

    Args:
        value (int): The integer to encode.

    Returns:
        bytes: The encoded VarInt as bytes.
    """
    out = bytearray()
    while True:
        if (value & ~SEGMENT_BITS) == 0:
            out.append(value)
            return bytes(out)
        else: 
            out.append((value & SEGMENT_BITS) | CONTINUE_BIT)
            value >>= 7


def decode_varint(data: bytes) -> int:
    """
    Decodes a VarInt from minecraft's format.

    Args:
        data (bytes): The bytes containing the VarInt.

    Returns:
        int: The decoded integer.
    """
    value = 0
    shift = 0

    for index in range(len(data)):
        current_byte = data[index]
        value |= (current_byte & SEGMENT_BITS) << shift

        if (current_byte & CONTINUE_BIT) == 0:
            return value

        shift += 7
        if shift >= 32:
            raise ValueError("VarInt is too big")

    raise ValueError("Incomplete VarInt")


def MakeHandShakePacket(host: str, port: int, next_state: int) -> bytes:
    """
    Creates a Handshake packet for the Minecraft protocol.

    Args:
        host (str): The server hostname.
        port (int): The server port.
        next_state (int): The next state (1 for status).

    Returns:
        bytes: The constructed Handshake packet.
    """
    # Create the data required for a Handshake packet
    packet_id = b'\x00'
    protocol_version = encode_varint(4) 
    server_address = encode_varint(len(host)) + host.encode('utf-8')
    server_port = port.to_bytes(2, byteorder='big')
    intent = encode_varint(next_state)

    packet_data = (packet_id + protocol_version + server_address + server_port + intent)

    # Packets are prefixed with their length as a VarInt
    return encode_varint(len(packet_data)) + packet_data


def MakeStatusRequestPacket() -> bytes:
    """
    Creates a Status Request packet for the Minecraft protocol.
    """
    # Create the data required for a Status Request packet
    packet_id = b'\x00'

    return encode_varint(len(packet_id)) + packet_id


@dataclass
class StatusResponse:
    """
    Response structure for the Minecraft server status.
    """
    version_name: str
    version_protocol: int
    players_max: int
    players_online: int
    description: str


async def decode_status_response(reader: asyncio.StreamReader) -> StatusResponse:
    """
    Decodes the status response from the Minecraft server.
    
    Args:
        reader (asyncio.StreamReader): The stream reader to read data from.
    
    Returns:
        StatusResponse: The decoded status response.
    """
    packet_length = decode_varint(await reader.read(3))
    _ = decode_varint(await reader.read(2))
    data = (await reader.read(packet_length - 3)).decode('utf-8')

    json_data = json.loads(data)
    return StatusResponse(
        version_name=json_data['version']['name'],
        version_protocol=json_data['version']['protocol'],
        players_max=json_data['players']['max'],
        players_online=json_data['players']['online'],
        description=json_data['description']
    )


async def run_player_count_client():
    """
    Asynchronously monitors the Minecraft server player count and stops the server and EC2 instance when no players are online.

    Raises:
        ConnectionError: If unable to connect to the Minecraft server.
    """
    while True:
        await asyncio.sleep(PLAYER_CHECK_INTERVAL)
        
        try:
            reader, writer = await asyncio.open_connection('localhost', 25565)
        except Exception as e:
            print(f"Could not connect to server: {e}")
            print("Server is likely offline, retrying...")
            await asyncio.sleep(PLAYER_CHECK_INTERVAL)
            continue

        handshake_packet = MakeHandShakePacket('localhost', 25565, 1)
        writer.write(handshake_packet)
        await writer.drain()

        status_request_packet = MakeStatusRequestPacket()
        writer.write(status_request_packet)
        await writer.drain()

        # Read the response length as a VarInt
        response = await decode_status_response(reader)
        
        if response.players_online == 0:
            try:
                await stop_server_command()
            except Exception as e:
                print(f"Error stopping server: {e}")
            finally:
                writer.close()
                await writer.wait_closed()
            return

        # Close the socket connection
        writer.close()
        await writer.wait_closed()
        

async def stop_server_command():
    """
    Asynchronously sends the "stop" command to the Minecraft server via RCON.
    
    Raises:
        ConnectionError: If unable to connect to the RCON server.
        PermissionError: If RCON authentication fails.    
    """
    host = os.getenv("RCON_HOST", "localhost")
    port = int(os.getenv("RCON_PORT", "25575"))
    password = os.getenv("RCON_SECRET", "123456")

    try:
        reader, writer = await asyncio.open_connection(host, port)
    except Exception as e:
        print(f"Could not connect to RCON server: {e}")
        raise ConnectionError("Failed to connect to RCON server") 
    
    try:
        auth_request_id = random.randint(1, 2147483647)
        auth_id, auth_type, _ = await rcon_send_and_recv(reader, writer, auth_request_id, 3, password)

        # On auth failure, the server responds with request id = -1.
        if auth_id == -1:
            raise PermissionError("RCON authentication failed (request id = -1). Check RCON_SECRET")

        if auth_id != auth_request_id or auth_type != 2:
            raise PermissionError("Unexpected RCON auth response. Check RCON port/password and server config.")

        cmd_request_id = random.randint(1, 2147483647)
        await rcon_send_and_recv(reader, writer, cmd_request_id, 2, "stop")
    finally:
        writer.close()
        await writer.wait_closed()


async def rcon_send_and_recv(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    request_id: int,
    packet_type: int,
    payload: str,
) -> tuple[int, int, str]:
    payload_bytes = payload.encode("ascii")
    body = struct.pack("<ii", request_id, packet_type) + payload_bytes + b"\x00\x00"
    writer.write(struct.pack("<i", len(body)) + body)
    await writer.drain()

    # Read response
    size_raw = await reader.readexactly(4)
    (size,) = struct.unpack("<i", size_raw)
    data = await reader.readexactly(size)

    resp_id, resp_type = struct.unpack("<ii", data[:8])
    # Payload is everything up to the first null byte after the header
    payload_end = data.find(b"\x00", 8)
    resp_payload = data[8:payload_end].decode("ascii", errors="replace") if payload_end != -1 else ""
    return resp_id, resp_type, resp_payload


async def RunAWSStopInstance():
    """
    Stops the EC2 instance using AWS CLI.
    """
    try:
        print(f"Stopping EC2 instance {INSTANCE_ID}...")
        subprocess.run(
            ["aws", "ec2", "stop-instances", "--instance-ids", INSTANCE_ID], 
            text=True, 
            check=True, 
            capture_output=True
            )
    except subprocess.CalledProcessError as e:
        print(f"Failed to stop EC2 instance: {e.stderr}")
        print("Halting the server instead.")
        subprocess.run(["sudo", "shutdown", "-h", "now"])

async def main():
    await run_player_count_client()

    # Wait for the server process to exit before stopping the EC2 instance
    while True:
        await asyncio.sleep(2)
        if not psutil.pid_exists(SERVER_PID):
            break

    await RunAWSStopInstance()
    exit(0)    
    

if __name__ == "__main__":
    # Run the player count monitoring client
    asyncio.run(main())

