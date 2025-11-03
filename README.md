# UIMPI
# Performance Limiter for BeamMP

A lightweight and optimized performance rating system for BeamMP servers. Automatically calculates vehicle performance ratings and enforces server limits in real-time.

![UI Screenshot 1](https://github.com/5DROR5/UIMPI/blob/main/PNG/1.png?raw=true)
![UI Screenshot 2](https://github.com/5DROR5/UIMPI/blob/main/PNG/2.png?raw=true)

## Features

- **Real-time Performance Rating** - Calculates PI (Performance Index) based on power, weight, drivetrain, grip, and braking
- **Automatic Enforcement** - Freezes vehicles exceeding the server limit
- **Visual UI App** - In-game display showing vehicle stats and rating class (D/C/B/A)
- **Server Control** - Set custom performance limits for balanced gameplay.

## Configuration

Edit the limit in `main.lua`:
```lua
local MAX_PERFORMANCE_RATING = 120  -- Change this value (0-499)
```

## License

This project is open source. Feel free to modify and distribute.

---

**Made for the BeamMP community** 🚗💨
