class ConfigTemplates:
    def __init__(self):
        self.templates = {
            "aws": {
                "bucket": "your-bucket-name",
                "endpoint": "s3.amazonaws.com",
                "region": "us-east-1",
                "access_key": "your-access-key",
                "secret_key": "your-secret-key",
                "prefix": "proxmox/",
                "content": "backup,iso,vztmpl,snippets",
                "storage_class": "STANDARD",
                "multipart_chunk_size": 100,
                "max_concurrent_uploads": 3,
            },
            "minio": {
                "bucket": "your-bucket-name",
                "endpoint": "minio.example.com:9000",
                "region": "us-east-1",
                "access_key": "your-access-key",
                "secret_key": "your-secret-key",
                "prefix": "proxmox/",
                "content": "backup,iso,vztmpl,snippets",
                "storage_class": "STANDARD",
                "multipart_chunk_size": 100,
                "max_concurrent_uploads": 3,
            },
            "ceph": {
                "bucket": "your-bucket-name",
                "endpoint": "ceph-rgw.example.com:7480",
                "region": "default",
                "access_key": "your-access-key",
                "secret_key": "your-secret-key",
                "prefix": "proxmox/",
                "content": "backup,iso,vztmpl,snippets",
                "storage_class": "STANDARD",
                "multipart_chunk_size": 100,
                "max_concurrent_uploads": 3,
            },
            "wasabi": {
                "bucket": "your-bucket-name",
                "endpoint": "s3.wasabisys.com",
                "region": "us-east-1",
                "access_key": "your-access-key",
                "secret_key": "your-secret-key",
                "prefix": "proxmox/",
                "content": "backup,iso,vztmpl,snippets",
                "storage_class": "STANDARD",
                "multipart_chunk_size": 100,
                "max_concurrent_uploads": 3,
            },
        }

    def get_template(self, provider):
        return self.templates.get(provider, {})