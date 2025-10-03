class ProxmoxClient:
    def __init__(self, ip, username, password):
        self.ip = ip
        self.username = username
        self.password = password
        self.session = None

    def connect(self):
        import requests
        from requests.auth import HTTPBasicAuth

        url = f"https://{self.ip}:8006/api2/json/"
        self.session = requests.Session()
        self.session.auth = HTTPBasicAuth(self.username, self.password)
        self.session.verify = False  # Disable SSL verification for simplicity

        try:
            response = self.session.get(url)
            response.raise_for_status()
            print("Connected to Proxmox server successfully.")
        except requests.exceptions.RequestException as e:
            print(f"Failed to connect to Proxmox server: {e}")
            self.session = None

    def disconnect(self):
        if self.session:
            self.session.close()
            print("Disconnected from Proxmox server.")

    def is_connected(self):
        return self.session is not None

    def get_storage_config(self):
        if not self.is_connected():
            print("Not connected to Proxmox server.")
            return None

        url = f"https://{self.ip}:8006/api2/json/storage"
        response = self.session.get(url)
        return response.json() if response.ok else None

    def create_storage_config(self, config_data):
        if not self.is_connected():
            print("Not connected to Proxmox server.")
            return False

        url = f"https://{self.ip}:8006/api2/json/storage"
        response = self.session.post(url, json=config_data)
        return response.ok

    def update_storage_config(self, storage_id, config_data):
        if not self.is_connected():
            print("Not connected to Proxmox server.")
            return False

        url = f"https://{self.ip}:8006/api2/json/storage/{storage_id}"
        response = self.session.put(url, json=config_data)
        return response.ok