# AURORA MATLAB/Simulink Simulation Execution & Submission Guide

This guide details how to execute the MATLAB simulation, construct the Simscape block model, structure your screen recording, and prepare your submission to satisfy the hackathon guidelines.

---

## 💻 1. Executing the MATLAB Physics Script

The script **`aurora_vsg_simulation.m`** has been placed in your project folder. Follow these steps to run it and export the figures:

1. **Open MATLAB**: Launch MATLAB (R2020a or newer recommended).
2. **Set Working Directory**: Set the MATLAB current folder path to your project folder:
   `c:\Users\Panshul\Desktop\aurora\`
3. **Open the Script**: Double-click `aurora_vsg_simulation.m` in the MATLAB file explorer.
4. **Run the Script**: Press the green **Run** button ($\mathbf{\blacktriangleright}$) in the Editor tab, or type `aurora_vsg_simulation` in the Command Window and press Enter.
5. **Adjusting Parameters**: You can modify the variables in the code to simulate different weather scenarios:
   - Decrease `solar` output to simulate cloud cover by reducing the multiplier.
   - Adjust `R_droop = 0.05` to test a 5% primary governor droop instead of 4%.
6. **Exporting Graphs**: 
   - In the figure window, go to **File ➔ Export Setup**.
   - Under **Rendering**, set resolution to `300 dpi` for high-resolution graphics.
   - Click **Export** and save as `.png` to insert into your presentation slides.

---

## 🔌 2. Building the Simulink Block Model (Simscape)

To show a physical block diagram in your video and slides (as shown in **Slide 11**), build the following structure in Simulink using the **Simscape Electrical** library:

```
[BESS Battery Block] ---> [Three-Phase Inverter (IGBT)] ---> [Three-Phase V-I Measurement]
                                 ^                                       |
                                 | (PWM gate pulses)                     v
                          [VSG Controller] <=============================+
                          (Frequency/Voltage feedback)                   |
                                                                         v
                                                                   [400V AC Bus]
                                                                         |
                                                                         v
                                                             [Three-Phase Dynamic Load]
                                                             (P1-P5 Shedding Feeders)
```

### Required Blocks & Settings:
1. **BESS Battery Block** (`Simscape / Electrical / Specialized Power Systems / Sources`):
   - Set type to **Lithium-Ion**.
   - Rated Capacity: `1200 Ah`, Nominal Voltage: `400 V`, Initial SoC: `15%`.
2. **Inverter (IGBT Bridge)** (`Specialized Power Systems / Power Electronics`):
   - Set to a **Three-Phase Bridge** configuration.
   - Connect the DC inputs to the Battery block and the AC outputs to the Bus.
3. **VSG Controller (Custom Feedback)**:
   - Create a subsystem that measures the bus frequency deviation ($\Delta f = f - 50$).
   - Implement the droop control law: $P = -K_{vsg} \cdot \Delta f$.
   - Feed the output into a **PWM Generator (3-phase, 2-level)** to drive the IGBT gate pulses.
4. **Three-Phase Dynamic Load** (`Specialized Power Systems / Elements`):
   - Use this block to represent the prioritized feeders.
   - Use step blocks connected to control inputs to trigger loads at specific intervals:
     - **Hospital Feeder (P1)**: Step at $T=7\text{s}$.
     - **Community Feeder (P2)**: Step at $T=30\text{s}$.
5. **Powergui** (`Specialized Power Systems`):
   - Drag this block anywhere in the top-level Simulink window. Set simulation type to **Discrete** with sample time `50e-6` ($50\mu\text{s}$).

---

## 📹 3. How to Structure Your Screen Recording

The hackathon requires a clear screen recording demonstrating the setup and execution. Structure your video as follows:

* **Introduction (0:00 - 0:45)**:
  - Show your face or introduce the team name (**Team SE7EN**).
  - Open the **AURORA Web Dashboard** and briefly explain the 5-source architecture.
* **Simulink Model Walkthrough (0:45 - 2:00)**:
  - Open MATLAB/Simulink and display the block diagram.
  - Explain the **Virtual Synchronous Generator (VSG)** subsystem, showing how feedback loops emulation frequency inertia.
* **Simulation Execution (2:00 - 3:30)**:
  - Run the simulation in real-time.
  - Show the frequency recovery curve on the scope. Point out how the frequency recovers from $0\text{ Hz}$ to $50\text{ Hz}$ in **87 seconds**, and how the **hospital load (P1)** remains active after $T=7\text{s}$.
* **Analysis & Conclusions (3:30 - 5:00)**:
  - Highlight the LCOE achievement ($0.11/kWh) and the 100% renewable fraction.
  - End by summarizing how the Digital Twin aligns with IEEE 1547 utility standards.
