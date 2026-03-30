import os
import pytest

def test_httpd_is_installed(host):
    assert host.package("httpd").is_installed

def test_httpd_running_and_enabled(host):
    service = host.service("httpd")
    assert service.is_running
    assert service.is_enabled

def test_wordpress_files_exist(host):
    assert host.file("/var/www/html/index.php").exists
    assert host.file("/var/www/html/wp-config.php").exists
    assert host.file("/var/www/html/wp-config.php").user == "apache"

def test_port_80_is_listening(host):
    # コンテナ内で 80番ポートが開いているか確認
    socket = host.socket("tcp://0.0.0.0:80")
    assert socket.is_listening
