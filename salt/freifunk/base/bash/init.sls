{# Default Shell #}
bash:
  pkg.installed:
    - refresh: True
    - names:
      - bash
      - bash-completion

{# Configuration #}
/etc/bash.bashrc:
  file.managed:
    - source: salt://bash/etc/bash.bashrc
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: bash
