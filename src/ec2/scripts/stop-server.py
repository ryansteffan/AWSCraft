"""
Minecraft Server Stop Script
This script connects to a Minecraft server to monitor player count and then stops the server and ec2 instance when no players are online in a given period of time.

Please refer to docs found here for Protocol details:
    - https://minecraft.wiki/w/Java_Edition_protocol/Packets
    - https://minecraft.wiki/w/Java_Edition_protocol/Server_List_Ping
    - https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
"""

import asyncio
import os
import socket

from anyio import sleep

# Define constants and load them from the environment
HOST = os.getenv('MINECRAFT_SERVER_HOST', "127.0.0.1")
SERVER_PORT = int(os.getenv('MINECRAFT_SERVER_PORT', "25574"))
RCON_PORT = int(os.getenv('MINECRAFT_SERVER_RCON_PORT', "25575"))
PLAYER_COUNT_INTERVAL = int(os.getenv('PLAYER_COUNT_INTERVAL_SECONDS', "5"))


"""
Creates a minecraft 1.6 server list ping packet.

Returns:
    bytes: The constructed server list ping packet.
"""
def create_16_server_list_ping_packet() -> bytes:
    packet_id = b'\xfe'
    server_list_ping_payload = b'\x01'
    packet_id_plugin_message = b'\xfa'
    length_of_string = b'\x00\x0b'
    string_identifier = b"\x00\x4D\x00\x43\x00\x7C\x00\x50\x00\x69\x00\x6E\x00\x67\x00\x48\x00\x6F\x00\x73\x00\x74"
    length_of_packet_body = str.encode(str(7 + len(HOST)), 'utf-16-be') 
    protocol_version = b'\x00\x4A'
    host_code_units = len(HOST).to_bytes(2, byteorder='big')
    hostname = str.encode(HOST, 'utf-16-be')
    port = SERVER_PORT.to_bytes(2, byteorder='big')

    return (packet_id + server_list_ping_payload + packet_id_plugin_message 
            + length_of_string + string_identifier + length_of_packet_body 
            + protocol_version + host_code_units + hostname + port)


"""
Parses out the response from a minecraft 1.6 server list ping.

Args:
    data (bytes): The raw response data from the server.

Returns:
    dict: A dictionary containing the parsed server information.
"""
def parse_16_server_list_ping_response(data: bytes) -> dict:
    BODY_START_DELIMITER = b'\x00\xa7\x00\x31\x00\x00'
    BODY_START_DELIMITER_LEN = len(BODY_START_DELIMITER)
    
    # Find the start of the body
    body_start_index = data.find(BODY_START_DELIMITER)
    header_removed_data = data[body_start_index + BODY_START_DELIMITER_LEN:]

    # Need at least two bytes for protocol version
    if len(header_removed_data) < 2:
        raise ValueError("Response data too short to contain protocol version.")

    protocol_version = int.from_bytes(header_removed_data[0:2], byteorder='big')
    remaining = header_removed_data[2:]

    decoded = remaining.decode('utf-16-be', errors='replace')

    # The response fields are separated by a double-null (\x00\x00)
    parts = decoded.split('\x00\x00')

    server_version = parts[0] if len(parts) > 0 else ''
    motd = parts[1] if len(parts) > 1 else ''
    current_players = parts[2] if len(parts) > 2 else '0'
    max_players = parts[3] if len(parts) > 3 else '0'

    # Clean stray null characters and non-digits from numeric fields
    server_version = server_version.replace('\x00', '')
    motd = motd.replace('\x00', '')
    current_players = current_players.replace('\x00', '')
    max_players = max_players.replace('\x00', '')

    try:
        current_players_i = int(current_players)
    except Exception:
        digits = ''.join([c for c in current_players if c.isdigit()])
        current_players_i = int(digits) if digits else 0

    try:
        max_players_i = int(max_players)
    except Exception:
        digits = ''.join([c for c in max_players if c.isdigit()])
        max_players_i = int(digits) if digits else 0

    return {
        "protocol_version": protocol_version,
        "server_version": server_version,
        "motd": motd,
        "current_players": current_players_i,
        "max_players": max_players_i,
    }

"""
Asynchronous client to periodically ping the Minecraft server for player count.

Returns:
    None
"""
async def player_count_client():
        while True:
            await sleep(PLAYER_COUNT_INTERVAL)
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client_socket:
                client_socket.connect((HOST, SERVER_PORT))
                ping_packet = create_16_server_list_ping_packet()
                client_socket.sendall(ping_packet)
                response = client_socket.recv(4096)
                print("Received server response:", response)
                server_info = parse_16_server_list_ping_response(response)
                print("Player Count Info: ", server_info["current_players"])                


"""
Asynchronous function to send a stop command to the Minecraft server via RCON.

Returns:
    None
"""
async def send_stop_command():
    print("Sending stop command to the server...")
    print("Stop command functionality not yet implemented.")
    # with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client_socket:
    #     client_socket.connect((HOST, RCON_PORT))
    #     # Send the stop command to the server


if __name__ == "__main__":
    print("Starting player count client...")
    asyncio.run(player_count_client())
