# sIndoor SDK

## 0.1.1

- The engine of sIndoor 0.2.11: routes on the device keep the rules of zones for their movement profile (closed, no
  through traffic, slow), as routes of the platform do. 0.1.0 ignored them.
- Positioning weighs learned cells by their readings, as on the server.

## 0.1.0

- First release: indoor routes, tours and positioning on the device (offline once a site is downloaded), the Open
  Platform client (sites' customer form with a map key, the full form with a token your server issues), phone sensors
  and Bluetooth beacons fed to the positioning, and a ready navigation screen on sMap maps (the site's levels, a level
  switcher, the blue dot, the route and its steps). Web (`@superrouteca/sindoor`, React `@superrouteca/sindoor-react`,
  the site editor `@superrouteca/sindoor-editor`), Flutter (`sindoor`, `sindoor_map`), iOS and macOS (Swift package
  `SIndoor`, `SIndoorMap`), Android (`ca.superroute:sindoor`, `ca.superroute:sindoor-map`), React Native
  (`@superrouteca/sindoor-react-native`).
