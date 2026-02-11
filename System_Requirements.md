# PIPE-CELL HMI SYSTEM REQUIREMENTS  
**Derived from PIPE-CELL HMI Rev B**

---

## 1. System Overview

The PIPE-CELL Human Machine Interface (HMI) shall provide a centralized interface for controlling, monitoring, and documenting automated pipe welding operations. The HMI shall integrate operator authentication, safety state awareness, weld schedule validation, scanning verification, welding execution, I/O monitoring, and comprehensive data logging.

The system is intended to support safety-critical industrial welding operations and shall enforce procedural, safety, and data integrity requirements throughout the welding lifecycle.

---

## 2. Operating Environment Requirements

- The HMI shall operate on a **Windows-based tablet**.
- The system shall provide access to standard Windows functionality while maintaining control over welding-related operations.
- The HMI shall support simultaneous operation of auxiliary applications without disrupting the PIPE-CELL application.

---

## 3. User Authentication & Access Control

### 3.1 Login
- The system shall require a **username and password** for access.
- Successful login shall associate the operator identity with all reporting and weld records.
- The system shall not automatically log out while applications are running.

### 3.2 Operator Identification
- The logged-in operator’s name shall be displayed within the PIPE-CELL application.
- Operator identity shall be automatically populated in all weld records.

---

## 4. Desktop & Application Access

After successful login, the system shall display an application desktop that provides access to:
- PIPE-CELL application
- Video calling application
- Remote login application
- IMU log files
- Camera application
- Weld data files
- Standard Windows utilities

---

## 5. Safety State & Beacon Logic

The HMI shall display a **three-state beacon indicator** reflecting the system safety condition:

### 5.1 Red State – Do Not Enter
- Doors closed
- Emergency Stops (E-Stop) and Controlled Stops (C-Stop) disengaged
- Anchor magnets engaged
- Trap doors engaged
- Temperature within allowable range

### 5.2 Amber State – Assistance Required
- Doors open **or**
- E-Stop or C-Stop engaged
- Anchor magnets engaged
- Trap doors closed

### 5.3 Green State – Safe to Move
- Doors closed
- E-Stop and C-Stop disengaged
- Anchor magnets disengaged
- Trap doors open

The HMI shall prevent progression into unsafe states based on these conditions.

---

## 6. Weld Schedule Manager (WSM) Integration

- The system shall pull the **active Weld Schedule Manager (WSM)** automatically.
- Essential welding variables shall be displayed to the operator for verification.
- The WSM unique ID and essential variables shall be recorded with each weld.
- A PDF link to the active WSM shall be accessible from the HMI.

---

## 7. New Weld Initialization

### 7.1 Pre-Check List
The system shall require confirmation of a pre-check list including, but not limited to:
- Correct wire and wire diameter
- Correct shielding gas, pressure, and availability
- Correct pre-heat temperature
- Clean nozzles and tips
- Ground cable connected
- E-Stops and C-Stops disengaged
- Grinding disks serviceable
- Doors closed
- Robot path unobstructed
- Anchor magnets engaged
- Trap doors shut
- Correct WSM loaded
- No personnel inside the cell
- Power supply and generator operational
- Air supply active
- Beacon light functional

### 7.2 Confirmation Logic
- The “New Weld” function shall be locked until the checklist is confirmed.
- Confirmation shall be recorded in the weld record.

---

## 8. Weld Data Entry Requirements

### 8.1 Mandatory Fields
- Weld ID (mandatory and unique)
- Operator (auto-filled from login)

### 8.2 Optional / Persistent Fields
- Project name
- Client name
- Comments
- Upstream and downstream heat numbers

### 8.3 Automatic Data Population
The system shall automatically populate:
- Pipe diameter
- Wall thickness
- Bevel angle
- Pre-heat temperature
- Wire type and diameter
- Shielding gas composition
- Operator name
- Location coordinates (GPS)

### 8.4 Data Validation
- The system shall prevent saving weld data until mandatory fields are complete.
- Weld ID duplication shall trigger a fault.

---

## 9. Scanning & Verification Requirements

### 9.1 Scan Validation
Following cycle start, the scanning process shall verify:
- Pipe diameter
- Wall thickness
- Bevel angle
- Hi/Low alignment
- Pre-heat temperature

All values shall be checked against WSM tolerances.

### 9.2 Fault Handling
- Out-of-tolerance conditions shall halt progression and generate summarized fault notifications.
- Weldments outside robot reach limits shall generate position fault messages.
- External clamp obstructions shall trigger partial scan and partial weld options.

### 9.3 Scan Completion
- Scan completion shall generate a spider graph.
- Scan data shall be saved using the naming convention:  
  **WeldID_SD**

---

## 10. Welding Execution Requirements

### 10.1 Welding Screen
The welding screen shall display:
- Individual robot status (welding or grinding)
- Time remaining per robot
- Total remaining weld time
- Positional indicators around the pipe

### 10.2 Controls
- Fast forward, rewind, and play controls shall be locked until the corresponding robot is C-Stopped.
- Position jump commands shall be entered via on-screen keyboard.
- Door opening or external fault signals shall trigger a system-wide C-Stop.

### 10.3 Completion
- Selecting “Finish Weld” shall:
  - Stop data logging
  - Save weld data logs
  - Return the system to the initial screen

---

## 11. I/O Monitoring

- The I/O monitoring screen shall be accessible at any time.
- Accessing the I/O screen shall not disrupt active welding operations.
- The screen shall display:
  - Signals to robots
  - Signals from robots
  - Welder status
  - Sensor inputs
  - Safety interlocks

---

## 12. Data Logging & File Management

### 12.1 File Structure
Each weld shall generate a unique folder identified by the weld ID containing:
- **WRD** – Weld record data (screen capture, CSV, or PDF)
- **SD** – Scan spider graph and/or scan data
- **WDL** – Welding machine parameter logs
- **JPG** – Photo of completed weld showing weld ID

### 12.2 File Integrity
- Duplicate weld IDs shall trigger a fault.
- The operator must delete existing files before reusing a weld ID.

### 12.3 Multi-Station Data Collation
- The system shall support post-process collation of weld data from multiple welding stations into a single dataset spanning root to cap passes.

---

## 13. Sensor & Input Signal Requirements

The system shall monitor and respond to the following inputs:
- Temperature sensor (minimum pre-heat enforcement)
- IMU (impact and operating temperature limits)
- Fronius welders (low gas, arc fault, lost arc)
- Fanuc robots (collision detection)
- Trap door position sensors
- Man door sensors
- Anchor magnet status
- Scanner system (i-Cube)

Faults shall be logged and, where permitted, manually cleared by the operator.

---

## 14. Safety & Traceability Requirements

- Unsafe conditions shall prevent system operation.
- All faults, overrides, and operator actions shall be logged.
- Weld records shall provide full traceability from scan through final weld completion.

---

## 15. End of Requirements
