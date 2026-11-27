# -*- mode: ruby -*-
# Zabbix 8.0 LTS na Debianu 13 (VirtualBox + shell provisioning)

Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-13"
  config.vm.hostname = "zabbix8"

  # Web (Apache) -> jen na loopback hostitele: http://127.0.0.1:8080/zabbix
  config.vm.network "forwarded_port", guest: 80, host: 8080,
                    host_ip: "127.0.0.1", id: "http"

  # SSH omezeno na loopback hostitele (pouzivejte: vagrant ssh)
  config.vm.network "forwarded_port", guest: 22, host: 2222,
                    host_ip: "127.0.0.1", id: "ssh"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "zabbix8-debian13"
    vb.cpus   = 2
    vb.memory = 2048
  end

  # Hesla se NEUKLADAJI v repozitari. Volitelne se predaji z prostredi hostitele
  # (napr. ZBX_DB_PASSWORD=... vagrant up). Kdyz nejsou zadana, vygenerují se
  # nahodne uvnitr VM a ulozi do /etc/zabbix/.db_password (jen root).
  config.vm.provision "shell", path: "scripts/01-install-zabbix.sh",
    env: {
      "ZBX_DB_PASSWORD" => ENV["ZBX_DB_PASSWORD"].to_s,
      "ZBX_SERVER_NAME" => ENV["ZBX_SERVER_NAME"].to_s,
      "ZBX_TIMEZONE"    => ENV["ZBX_TIMEZONE"].to_s
    }

  config.vm.provision "shell", path: "scripts/02-verify.sh"
end
