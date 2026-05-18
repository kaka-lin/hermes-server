import socket, threading, sys, time

def forward(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data: break
            dst.sendall(data)
    except:
        pass
    finally:
        src.close()
        dst.close()

# 讀取使用者傳入的 port，如果沒有傳，預設為 18800
port = 18800
if len(sys.argv) > 1:
    port = int(sys.argv[1])

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', port))
server.listen(5)
print(f'Proxy listening on 127.0.0.1:{port} -> forwarding to host.docker.internal:{port}')

while True:
    client, addr = server.accept()
    try:
        # Magic IP for Docker Desktop Mac host
        remote = socket.create_connection(('192.168.65.254', port))
        threading.Thread(target=forward, args=(client, remote), daemon=True).start()
        threading.Thread(target=forward, args=(remote, client), daemon=True).start()
    except Exception as e:
        client.close()
