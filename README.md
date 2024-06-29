# wireguard control
wg-ctl an openwrt wireguard setup helper script

+ Grabs config from file instead of environment variables
+ Add local routes and DNS for clients
+ Automatically adds to network config

Currently only 1 route may be added, and it sets the vpn in client mode

To do:
* take lists of routes
* built-in option to retrieve file remotely
* add other vpn config modes e.g s2s and server
* import/export config to different formats e.g uci and file
