# UIMPI
# Performance Limiter for BeamMP

A lightweight and optimized performance rating system for BeamMP servers. Automatically calculates vehicle performance ratings and enforces server limits in real-time.

![UI Screenshot 1](https://github.com/5DROR5/UIMPI/blob/main/PNG/1.png?raw=true)
![UI Screenshot 2](https://github.com/5DROR5/UIMPI/blob/main/PNG/2.png?raw=true)

---

## Features

### Performance Rating
- Calculates a **Performance Index (PI)** for every vehicle in real-time
- Rating factors: engine power, torque, weight, drivetrain type (RWD/FWD/AWD), tire grip, and braking force
- Four rating classes: **D / C / B / A**
- Dual-motor EV support

### Enforcement
- Vehicles exceeding the server limit are **automatically frozen**
- A **2-point display offset** is applied to the visible limit — players see a slightly lower number than the actual enforcement threshold, compensating for mid-drive fluctuations
- Frozen vehicles receive a clear in-game banner explaining the reason and how to fix it

### In-Game UI App
- Displays live vehicle stats: HP, weight, torque, brakes, grip, drivetrain, RPM, gearbox, induction type
- Color-coded stat indicators showing each value's impact on the rating:
  - 🔴 **Red** — Max Impact: increasing this value will no longer affect the rating
  - 🟠 **Orange** — Affects Rating: changing this value will raise or lower the rating
  - 🟢 **Green** — Below Minimum Impact: decreasing this value will no longer affect the rating
- Rating badge pulses red with a ⚠ warning when the vehicle is over the limit
- Toggle stats panel by clicking the rating badge

### Vote System *(optional)*
- Players vote to change the server performance limit
- Configurable options, duration, and admin controls
- Real-time vote results with progress bars in the UI

### Multilingual Support
- Language is detected automatically from the player's BeamNG settings

### Commands

| Command | Who | Description |
|---|---|---|
| `/setlimit [n]` | Admin | Change the limit instantly |
| `/startvote` | Admin | Start a community vote |
| `/endvote` | Admin | End a vote early |

---

## Configuration

Edit `Server/UIMPI/config.json`:

```json
{
  "max_performance_rating": 122,
  "display_offset": 2,
  "admins": ["YourPlayerName"],

  "vote_enabled": false,
  "vote_duration": 20,
  "vote_options": [80, 100, 120, 150, 200, 250]
}
```

| Field | Description |
|---|---|
| `max_performance_rating` | The actual enforcement threshold |
| `display_offset` | Subtracted from the displayed limit (recommended: `2`) |
| `admins` | Player names with admin privileges |
| `vote_enabled` | Enable the community vote system |
| `vote_duration` | Vote duration in seconds |
| `vote_options` | Available limit options players can vote for |

---

## License

[The Unlicense](https://unlicense.org) — public domain.

---

**Made for the BeamMP community** 🚗💨
