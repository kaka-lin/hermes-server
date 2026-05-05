import socket, threading, sys, time

def forward(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data: break
            dst.sendall(data)
    except: pass
    finally:
        src.close()
        dst.close()

def start_proxy(local_port, target_ip, target_port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(('127.0.0.1', local_port))
        server.listen(5)
        print(f'Proxy listening on 127.0.0.1:{local_port} -> {target_ip}:{target_port}')
    except Exception as e:
        print(f"Failed to bind {local_port}: {e}")
        return

    while True:
        try:
            client, addr = server.accept()
            remote = socket.create_connection((target_ip, target_port))
            threading.Thread(target=forward, args=(client, remote), daemon=True).start()
            threading.Thread(target=forward, args=(remote, client), daemon=True).start()
        except Exception as e:
            print(f"Error on {local_port}: {e}")
            try: client.close()
            except: pass

if __name__ == "__main__":
    # Magic IP for Docker Desktop host
    HOST_IP = '192.168.65.254'
    
    # 啟動 9223 (langlive-main)
    threading.Thread(target=start_proxy, args=(9223, HOST_IP, 9223), daemon=True).start()
    
    # 啟動 9224 (langlive-sms)
    threading.Thread(target=start_proxy, args=(9224, HOST_IP, 9224), daemon=True).start()
    
    while True:
        time.sleep(60)
