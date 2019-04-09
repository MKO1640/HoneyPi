[ -z $BASH ] && { exec bash "$0" "$@" || exit; }
#!/bin/bash
# file: install.sh
#
# This script will install required software for HoneyPi.
# It is recommended to run it in your home directory.
#

# check if sudo is used
if [ "$(id -u)" != 0 ]; then
  echo 'Sorry, you need to run this script with sudo'
  exit 1
fi

# target directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# error counter
ERR=0

# enable I2C on Raspberry Pi
# enable 1-Wire on Raspberry Pi
echo '>>> Enable I2C and 1-Wire'
if grep -q 'i2c-dev' /etc/modules; then
  echo 'Seems i2c-dev module already exists, skip this step.'
else
  echo 'i2c-dev' >> /etc/modules
fi
if grep -q 'w1_gpio' /etc/modules; then
  echo 'Seems w1_gpio module already exists, skip this step.'
else
  echo 'w1_gpio' >> /etc/modules
fi
if grep -q 'w1_therm' /etc/modules; then
  echo 'Seems w1_therm module already exists, skip this step.'
else
  echo 'w1_therm' >> /etc/modules
fi
if grep -q 'dtoverlay=w1-gpio' /boot/config.txt; then
  echo 'Seems w1-gpio parameter already set, skip this step.'
else
  echo 'dtoverlay=w1-gpio' >> /boot/config.txt
fi
if grep -q 'dtparam=i2c_arm=on' /boot/config.txt; then
  echo 'Seems i2c_arm parameter already set, skip this step.'
else
  echo 'dtparam=i2c_arm=on' >> /boot/config.txt
fi

# Enable Wifi on Raspberry Pi 1 & 2
if grep -q 'net.ifnames=0' /boot/cmdline.txt; then
  echo 'Seems net.ifnames=0 parameter already set, skip this step.'
else
  echo 'net.ifnames=0' >> /boot/cmdline.txt
fi

# change hostname to http://HoneyPi.local
echo '>>> Change Hostname to HoneyPi'
sudo sed -i 's/127.0.1.1.*raspberry.*/127.0.1.1 HoneyPi/' /etc/hosts
sudo bash -c "echo 'HoneyPi' > /etc/hostname"

#rpi-scripts
echo '>>> Install software for measurement python scripts'
apt-get install -y rpi.gpio python-smbus python-setuptools python3-pip || ((ERR++))
easy_install pip
pip install thingspeak
python3 -m pip install --upgrade pip setuptools wheel
python3 -m pip install numpy
pip3 install bme680
pip3 install Adafruit_DHT

#rpi-webinterface
echo '>>> Install software for Webinterface'
apt-get install -y lighttpd php7.0-cgi || ((ERR++))
lighttpd-enable-mod fastcgi fastcgi-php
service lighttpd force-reload

echo '>>> Create www-data user'
groupadd www-data
usermod -G www-data -a pi
# TODO: move files
# set file rights
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html

# give www-data all right for shell-scripts
echo '>>> Give shell-scripts rights'
if grep -q 'www-data ALL=NOPASSWD: ALL' /etc/sudoers; then
  echo 'Seems www-data already has the rights, skip this step.'
else
  echo 'www-data ALL=NOPASSWD: ALL' | sudo EDITOR='tee -a' visudo
fi

# Install software for surfstick
echo '>>> Install software for Surfsticks'
apt-get install -y usb-modeswitch || ((ERR++))

#wifi
echo '>>> Setup Wifi Configuration'
cp overlays/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf

# Autostart
echo '>>> Put Measurement Script into Autostart'
if grep -q "$DIR/rpi-scripts/main.py" /etc/rc.local; then
  echo 'Seems measurement main.py already in rc.local, skip this step.'
else
  sed -i -e '$i \(sleep 5;python3 '"$DIR"'/rpi-scripts/main.py)&\n' /etc/rc.local
fi

# AccessPoint
echo '>>> Set Up Raspberry Pi as Access Point'
apt-get install -y dnsmasq hostapd || ((ERR++))
systemctl stop dnsmasq
systemctl stop hostapd
# Configuring a static IP
cp overlays/dhcpcd.conf /etc/dhcpcd.conf
systemctl daemon-reload
service dhcpcd restart
# Configuring the DHCP server (dnsmasq)
cp overlays/hostapd.conf /etc/hostapd/hostapd.conf
cp overlays/hostapd /etc/default/hostapd
# Start it up
systemctl start hostapd
systemctl start dnsmasq
# Add routing and masquerade
cp overlays/sysctl.conf /etc/sysctl.conf
sh -c "iptables-save > /etc/iptables.ipv4.nat"
iptables -t nat -A  POSTROUTING -o eth0 -j MASQUERADE
if grep -q 'iptables-restore < /etc/iptables.ipv4.nat' /etc/rc.local; then
  echo 'Seems iptables-restore < /etc/iptables.ipv4.nat already in rc.local, skip this step.'
else
  sed -i -e '$i \iptables-restore < /etc/iptables.ipv4.nat\n' /etc/rc.local
fi

# Replace HoneyPi files with latest release
if [ $ERR -eq 0 ]; then
  sh update.sh || ((ERR++))
else
  echo '>>> Something went wrong. Updating skiped.'
fi

echo
if [ $ERR -eq 0 ]; then
  echo '>>> All done. Please reboot your Pi :-)'
else
  echo '>>> Something went wrong. Please check the messages above :-('
fi