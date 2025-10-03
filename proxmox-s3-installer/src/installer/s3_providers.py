def get_s3_providers():
    return [
        {
            "name": "AWS S3",
            "endpoint": "s3.amazonaws.com",
            "region": "us-east-1"
        },
        {
            "name": "MinIO",
            "endpoint": "minio.example.com:9000",
            "region": "us-east-1"
        },
        {
            "name": "Ceph RadosGW",
            "endpoint": "ceph-rgw.example.com:7480",
            "region": "default"
        },
        {
            "name": "Wasabi",
            "endpoint": "s3.wasabisys.com",
            "region": "us-east-1"
        },
        {
            "name": "DigitalOcean Spaces",
            "endpoint": "nyc3.digitaloceanspaces.com",
            "region": "nyc3"
        },
        {
            "name": "Linode Object Storage",
            "endpoint": "us-east-1.linodeobjects.com",
            "region": "us-east-1"
        },
        {
            "name": "Backblaze B2",
            "endpoint": "s3.us-west-002.backblazeb2.com",
            "region": "us-west-002"
        },
        {
            "name": "Scaleway Object Storage",
            "endpoint": "s3.fr-par.scw.cloud",
            "region": "fr-par"
        },
        {
            "name": "IBM Cloud Object Storage",
            "endpoint": "s3.us-south.cloud-object-storage.appdomain.cloud",
            "region": "us-south"
        },
        {
            "name": "OVH Object Storage",
            "endpoint": "s3.gra.perf.cloud.ovh.net",
            "region": "gra"
        },
        {
            "name": "Other",
            "endpoint": "",
            "region": ""
        }
    ]