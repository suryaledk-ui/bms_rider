# Calibration Reference — BMS Rider (generated from research)

Target segment locked: **generic Chinese packs (48/60/72V) + Komaki class**.
All values below are literature/field-derived priors. The app learns per-rider
corrections on top; these are the cold-start defaults.

## 1. Vehicle priors (already coded in `lib/src/range.dart` presets)

| Preset | Pack | Usable kWh | Curb kg | CdA | Crr | Rated psi | Top speed |
|---|---|---|---|---|---|---|---|
| Generic 48V 20Ah | 48V 20Ah | 0.88 | 80 | 0.58 | 0.018 | 32 | 35 |
| Generic 60V 20Ah | 60V 20Ah | 1.10 | 85 | 0.58 | 0.018 | 32 | 45 |
| Generic 60V 30Ah | 60V 30Ah | 1.66 | 95 | 0.60 | 0.018 | 32 | 50 |
| Generic 72V 30Ah | 72V 30Ah | 1.99 | 100 | 0.60 | 0.018 | 32 | 55 |
| Komaki SE Eco | 62V 35Ah | 2.00 | 100 | 0.65 | 0.016 | 32 | 60 |
| Komaki SE Sport | 74V 44Ah | 3.00 | 100 | 0.65 | 0.016 | 32 | 80 |
| Komaki XGT KM | 60V 34Ah | 1.88 | 90 | 0.60 | 0.018 | 32 | 25 |
| Komaki X-One | LFP 1.75–2.2 | 1.84 | 85 | 0.60 | 0.017 | 32 | 55 |

Real-world consumption anchors (measured): Ola S1 Pro 31 Wh/km Normal,
Ather 450X 32 Eco, Chetak C2501 29 Sport, iQube 2.2 30 Eco,
Xiaomi M365 Pro 16.7 @18 km/h, generic 48–72V class 29–32 city.

## 2. Physics model defaults (coded in RangeEstimator)

- ρ = 1.225 kg/m³, g = 9.81
- η: Eco 0.74, Sports 0.78, Hyper 0.80 (battery→wheel, incl. controller)
- P_aux = 3 W
- Reference speeds per mode: Eco 20, Sports 36, Hyper 47 km/h
- Wh/km table (computed): 10→11.5, 20→13.9, 30→17.9, 40→23.6,
  50→30.9, 55→35.1 (flat, 170 kg, calm, CdA 0.48, Crr 0.018)

## 3. Battery science thresholds

- **SOC**: Coulomb counting primary; OCV lookup only at edges (>90%/<10%).
  Mid-plateau voltage-only error ±5–12% (NMC). Reset at full charge and
  after ≥30 min rest.
- Current deadband: |I| < 0.5–1 A (cheap BMS) — do not integrate idle.
- Coulombic efficiency ≈ 0.99–0.998; recharge factor k = 1/CE.
- **DCIR sag** @1C: 48V fresh ≈2.4V (5%), aged 2× ≈4.8V (10%).
  Flag R > 1.5× fresh; degrade at 2×.
- **Cycle fade (NMC)**: 80% SOH at ~900–1400 cycles (consumer),
  450–800 (cheap). First-year fade 5–10%. EOL = 80%.
- **Calendar**: 25°C/50% ≈1–2%/yr; 35°C/100% ≈5–7%/yr.
- **Charger efficiency**: 0.85–0.92 (default 0.88).
  SOH = wallWh × 0.88 / nominal.
- **Cell spread**: rest ≤30 mV normal, >50 warn, >80 bad;
  under 1C load >100–150 mV bad.
- **Temp**: 5°C ≈ −10% capacity, 0°C ≈ −12% range (fleet study);
  DCIR ×2.1 @0°C, ×4.5 @−10°C. Charge <0°C or >45°C = red.

## 4. Diagnostics thresholds

- **Trigger**: efficiency residual ≥ +6% median over last 10 rides with
  ≥8/10 positive; escalate at +10%. Use CUSUM k=0.5, h=5.0.
- False-positive budget ≤ 0.02% per rider-day; require ≥2 independent
  signals × ≥3 consecutive days.
- **Tyre**: ~3% range lost per 1 psi below spec; 25 vs 35 psi = +20%
  consumption. Alert at sustained +8–10%.
- **Brake drag**: coast-down decel > baseline +0.07 m/s² ×2 rides
  (healthy 25 km/h coast = 0.28–0.36 m/s²).
- **Bearing**: +1.5–4% energy only; needs IMU 20–60 Hz envelope for
  "suspected" label.
- **Wind = #1 false-positive**: 10 km/h headwind @25 km/h = +25–30%.
  Never attribute a single ride to hardware before checking wind.
- **Grade**: 1% = +15–20% @25 km/h; regen recovers 15–50%.
- **Stop-go**: +6–22% (2–6 stops/km); one stop @25 km/h ≈ 0.67 Wh.
- **Cold**: 0°C ≈ −12% range (Apollo 512k-ride fleet study).

## 5. Validation datasets (free/open)

1. Dublin DualEMobilityData (GitHub, MIT) — 30 scooter trips, full Wh/km +
   slope + wind + mass → primary unit-test ground truth.
2. Autocar full-drain tests (Ola/Ather/iQube/Chetak) — integration tests.
3. Racewicz & Kazimierczuk (Sciendo) — per-speed Wh/km 10–90 km/h.
4. Ben Katz 48V hub dyno + QS-205 datasheet — η(T,ω) curves.
5. syssi/esphome-jbd-bms — real JBD frame dumps → parser tests.
6. Xiaomi M365 Pro test — 16.7 Wh/km @18 km/h spot check.
