from setuptools import setup, find_packages

setup(
    name='proxmox-s3-installer',
    version='0.1.0',
    author='Your Name',
    author_email='your.email@example.com',
    description='A script to configure S3 storage for Proxmox VE',
    long_description=open('README.md').read(),
    long_description_content_type='text/markdown',
    url='https://github.com/yourusername/proxmox-s3-installer',
    packages=find_packages(where='src'),
    package_dir={'': 'src'},
    install_requires=[
        'paramiko',
        'click',
        'PyYAML',
        # Add other dependencies as needed
    ],
    entry_points={
        'console_scripts': [
            'proxmox-s3-installer=main:main',  # Adjust according to your main function location
        ],
    },
    classifiers=[
        'Programming Language :: Python :: 3',
        'License :: OSI Approved :: MIT License',
        'Operating System :: OS Independent',
    ],
    python_requires='>=3.6',
)