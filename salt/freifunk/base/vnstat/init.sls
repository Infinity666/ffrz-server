{# Network Traffic Monitor #}
{% from 'config.jinja' import ifname %}

vnstat:
  pkg.installed:
    - refresh: True
    - name: vnstat
  service:
    - enabled
    - restart: True
    - require:
      - pkg: vnstat
      - file: /etc/vnstat.conf

{# Configuration #}
/etc/vnstat.conf:
  file.managed:
    - source: salt://vnstat/etc/vnstat.tmpl
    - template: jinja
    - user: root
    - group: vnstat
    - mode: 644


{# initialize interface #}
vnstat_{{ ifname }}:
  cmd.run:
    - name: /usr/bin/vnstat -u -i {{ ifname }}
    - onlyif: test ! -f /var/lib/vnstat/{{ ifname }}

vnstat_bat0:
  cmd.run:
    - name: /usr/bin/vnstat -u -i bat0
    - onlyif: test ! -f /var/lib/vnstat/bat0 && test "$(cat /proc/net/dev | grep -cw 'bat0')" -eq '1'

vnstat_tbb_fastd2:
  cmd.run:
    - name: /usr/bin/vnstat -u -i tbb_fastd2
    - onlyif: test ! -f /var/lib/vnstat/tbb_fastd2 && test "$(cat /proc/net/dev | grep -cw 'tbb_fastd2')" -eq '1'

vnstat_vpn0:
  cmd.run:
    - name: /usr/bin/vnstat -u -i vpn0 && systemctl restart vnstat
    - onlyif: test ! -f /var/lib/vnstat/vpn0 && test -f /etc/openvpn/openvpn-vpn0.conf -o -f /etc/wireguard/vpn0.conf

vnstat_vpn1:
  cmd.run:
    - name: /usr/bin/vnstat -u -i vpn1 && systemctl restart vnstat
    - onlyif: test ! -f /var/lib/vnstat/vpn1 && test -f /etc/openvpn/openvpn-vpn1.conf -o -f /etc/wireguard/vpn1.conf

{# set correct file permissions #}
/var/lib/vnstat:
  file.directory:
    - user: vnstat
    - group: vnstat
    - recurse:
      - user
      - group

/var/lib/vnstat_dirperm:
  cmd.run:
    - name: /bin/chmod 755 /var/lib/vnstat
    - onlyif: "test $(stat -c '%a %n' /var/lib/vnstat | grep -cw 755 ) -eq '0'"

{# check needed vnstat restart #}
vnstat_restart:
  cmd.run:
    - name: /usr/bin/vnstat -u ; systemctl restart vnstat
    - onlyif: test ! -f /var/lib/vnstat/.{{ ifname }} || test ! -f /var/lib/vnstat/.tbb_fastd2 || "${test ! -f /var/lib/vnstat/.bat0 && test $(cat /proc/net/dev | grep -cw 'bat0') -eq '1'}"
