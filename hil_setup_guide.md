# AURORA Microgrid Hardware-in-the-Loop (HIL) Setup Guide

This guide details the steps required to transition the AURORA Digital Twin from a software-based simulation to a real-time **Hardware-in-the-Loop (HIL)** test bench using an **OPAL-RT** simulator and an industrial **SEL Controller**.

---

## 🔌 1. Physical Hardware & Wiring Map

The HIL test bench connects the **OPAL-RT Real-Time Simulator** (running the virtual physics of the 5-source microgrid) to the physical **SEL-3530 Real-Time Automation Controller (RTU)** (executing the EMS logic).

### A. System Architecture Diagram

```
+------------------------------------+          +------------------------------------+
|       OPAL-RT Simulator            |          |       Microgrid Controller         |
|   (Simulates Solar, Wind, Grid)    |          |          (SEL-3530 RTU)            |
|                                    |          |         (Executes EMS)             |
|   +----------------------------+   |          |   +----------------------------+   |
|   | Analog Outputs (DA)        |=======>======|   | Analog Inputs (AI)         |   |
|   | (Bus Freq, Volt, Battery)  |   |          |   | (Grid telemetry check)     |   |
|   +----------------------------+   |          |   +----------------------------+   |
|                                    |          |                                    |
|   +----------------------------+   |          |   +----------------------------+   |
|   | Digital Inputs (DI)        |======<=<=====|   | Digital Outputs (DO)       |   |
|   | (Breaker Trip Commands)    |   |          |   | (Relay/Breaker controls)   |   |
|   +----------------------------+   |          |   +----------------------------+   |
|                                    |          |                                    |
|   +----------------------------+   |          |   +----------------------------+   |
|   | Ethernet Port (DNP3/GOOSE) |======H=H=H===|   | Ethernet Port (DNP3/GOOSE) |   |
|   +----------------------------+   |          |   +----------------------------+   |
+------------------------------------+          +------------------------------------+
```

### B. Signal Connection Terminal Mapping

| OPAL-RT Terminal / Pin | Signal Type | Description | Controller Terminal (SEL-3530) |
|---|---|---|---|
| **DAC Slot 1, CH 1** | Analog Out ($0\text{–}10\text{V}$) | Grid Frequency ($0\text{–}60\text{Hz}$) | **AI Card, Slot 3, CH 1** |
| **DAC Slot 1, CH 2** | Analog Out ($0\text{–}10\text{V}$) | Grid AC Voltage ($0\text{–}480\text{V}$) | **AI Card, Slot 3, CH 2** |
| **DAC Slot 1, CH 3** | Analog Out ($0\text{–}5\text{V}$) | Battery State-of-Charge ($0\text{–}100\%$) | **AI Card, Slot 3, CH 3** |
| **DIN Slot 2, CH 1** | Digital In ($24\text{V}$) | Tripped/Close State (BESS Breaker) | **DO Card, Slot 4, Relay 1** |
| **DIN Slot 2, CH 2** | Digital In ($24\text{V}$) | Tripped/Close State (Solar Breaker) | **DO Card, Slot 4, Relay 2** |
| **RJ45 Port 1** | Ethernet (TCP/IP) | Modbus/DNP3 & IEC 61850 GOOSE | **RJ45 Port 1** (EMS commands) |

---

## 🛠️ 2. Simulink Model Partitioning (RT-LAB)

To run the Simulink model on OPAL-RT, you must divide the block diagram into two specific subsystems using the **RT-LAB** compiler:

### A. Subsystem Partitioning Rules
1. **`SM_physics` (Master Subsystem - Executed on Core 1)**:
   - Contains the solver math: VSG equations, swing equation, battery charging kinetics, line impedance, and solver parameters.
   - Run at a fixed step-size of **$50\mu\text{s}$** (`ode3` Bogacki-Shampine or `ode4` Runge-Kutta solver).
2. **`SC_console` (Console Subsystem - Executed on Host PC)**:
   - Contains the virtual dials, scopes, and parameters that the operator views during the test.
   - Run at a step-size of **$100\text{ms}$** (asynchronized communication).
3. **`OpComm` Insertion**:
   - You **must** insert an `OpComm` communication block at the input boundary of each subsystem to handle data serialization between cores.

---

## 🔌 3. Software & Protocol Integration

The controller reads analog values, runs EMS logic, and sends back breaker control overrides.

### A. Modbus Map (Telemetry & Control)

| Parameter | Modbus Type | Register Address | Scaling Factor |
|---|---|---|---|
| **Bus Frequency** | Read Input Register | `30001` | $\times 100$ ($50.00\text{ Hz} \rightarrow 5000$) |
| **Bus Voltage** | Read Input Register | `30002` | $\times 10$ ($400.0\text{ V} \rightarrow 4000$) |
| **Li-ion SoC** | Read Input Register | `30003` | $\times 100$ ($15.00\% \rightarrow 1500$) |
| **Solar Power Output**| Read Input Register | `30004` | $\times 1$ ($480\text{ kW} \rightarrow 480$) |
| **BESS Charge Power**| Write Holding Register| `40001` | $\times 1$ (kW setpoint) |
| **H2 Cell Enable** | Write Coil | `00001` | Binary (`1` = active, `0` = offline) |

### B. Fast Protective Relaying (IEC 61850 GOOSE)
For sub-cycle faults (e.g. BESS thermal overload or short circuit):
* **Config**: Assign multicast address `01-0C-CD-01-00-01` to the Ethernet network switch.
* **Performance**: Under-frequency relay trips the community load breaker in **$< 4\text{ms}$** from detection, matching the primary frequency droop limits.
