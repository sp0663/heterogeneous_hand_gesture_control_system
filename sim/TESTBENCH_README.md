# Gesture Recognition System - Full Integration Testbench

## Overview

The `tb_gesture_system_full.v` testbench provides comprehensive testing of the complete gesture recognition system, including:
- ✓ UART receive (landmark data from external source)
- ✓ Coordinate assembly (converting 8-bit bytes to 16-bit coordinates)
- ✓ Landmark storage (assembling 21 landmarks into 336-bit vectors)
- ✓ Gesture classification (recognizing hand gestures)
- ✓ Result transmission via UART TX

## Quick Start

### 1. Running the Testbench

```bash
cd /mnt/shared/C++programming/Hand_gesture_verilog/sim

# Using Vivado/ISE
xvlog tb_gesture_system_full.v ../rtl/*.v
xsim tb_gesture_system_full -gui

# Using ModelSim/QuestaSim
vlog tb_gesture_system_full.v ../rtl/*.v
vsim tb_gesture_system_full

# Using iverilog (free tool)
iverilog -o tb_gesture_system_full.vvp tb_gesture_system_full.v ../rtl/*.v
vvp tb_gesture_system_full.vvp
```

### 2. Adding Your Extracted Landmark Data

#### Method A: Using the Conversion Script (Recommended)

The `convert_landmarks.py` script automatically converts your landmark data into Verilog code:

```bash
# Prepare your landmark data file (21 landmarks)
# Format: JSON, CSV, or space-separated values

python3 convert_landmarks.py landmarks.json output.verilog
```

**Input file formats:**

```json
{
  "landmarks": [
    [1234, 5678],  // x0, y0
    [5678, 9012],  // x1, y1
    ...
    [...., ....]   // 21 total
  ]
}
```

Or CSV:
```
x0, y0
1234, 5678
5678, 9012
...
```

Or space-separated:
```
1234 5678
5678 9012
...
```

**Output:** The script generates Verilog code like:
```verilog
send_frame(
    336'hxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx,
    336'hyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
);
```

#### Method B: Manual Entry

Edit the testbench and find the **TEST CASE 4** section:

```verilog
// Inside tb_gesture_system_full.v, modify:
send_frame(
    336'h941e94ad953c95cb7ee081ac8359862467676ac16e1c75ef522956135c39664830a03f28519a68857fff,
    336'h1bf2272032dc45dd0cdb189725723cec00000d6a1e2e39020596139022183b3f45dd52b860b274d17fff
);
```

Replace with your landmark vectors (see conversion script).

#### Method C: UART Transmission

For testing with actual UART protocol:

```verilog
// Send landmarks via UART
send_uart_landmarks(5'd0,  16'hABCD, 16'hEF01);  // landmark 0: x=0xABCD, y=0xEF01
send_uart_landmarks(5'd1,  16'h1234, 16'h5678);  // landmark 1: x=0x1234, y=0x5678
send_uart_landmarks(5'd2,  16'hCAFE, 16'hBABE);  // landmark 2: x=0xCAFE, y=0xBABE
// ... repeat for all 21 landmarks
```

## Testbench Architecture

### Test Cases Included

1. **TEST CASE 1**: UART Landmark Reception
   - Sends all 21 landmarks via UART serial protocol
   - Verifies coordinate assembly and landmark storage
   - Checks `frame_ready` assertion

2. **TEST CASE 2**: Direct Frame Injection
   - Bypasses UART, directly loads 336-bit landmark vectors
   - Tests gesture classifier directly
   - Faster for multiple test iterations

3. **TEST CASE 3**: Multiple Gesture Sequences
   - Tests system with multiple frame inputs
   - Verifies proper signal handling

4. **TEST CASE 4**: Your Custom Landmark Data
   - Placeholder for your extracted landmarks
   - Replace with actual coordinate data

### Key Tasks

#### `send_uart_byte(data)`
Sends a single 8-bit byte via UART RX at ~115200 baud:
```verilog
send_uart_byte(8'hA5);
```

#### `send_uart_landmarks(id, x, y)`
Sends one complete landmark via UART (5 bytes total):
```verilog
send_uart_landmarks(5'd0, 16'h1234, 16'h5678);
```

#### `send_frame(x_vector, y_vector)`
Directly injects 21 landmarks (336 bits each):
```verilog
send_frame(
    336'h941e94ad953c95cb7ee081ac8359862467676ac16e1c75ef522956135c39664830a03f28519a68857fff,
    336'h1bf2272032dc45dd0cdb189725723cec00000d6a1e2e39020596139022183b3f45dd52b860b274d17fff
);
```

#### `wait_for_frame_ready(timeout)`
Waits for frame assembly to complete:
```verilog
wait_for_frame_ready(500000);  // timeout in clock cycles
```

## Understanding the Output

### Console Output
```
[TIMESTAMP] Frame Ready asserted!
[TIMESTAMP] === FRAME READY ===
    Landmarks X[335:0] = 0x941e94ad...
    Landmarks Y[335:0] = 0x1bf22720...
[TIMESTAMP] *** GESTURE DETECTED *** ID: 2
```

### Waveform Viewer (VCD)
Open `tb_gesture_system_full.vcd` to see:
- Clock and reset signals
- UART RX/TX waveforms
- Landmark coordinates assembly
- Gesture classification valid pulse
- Gesture ID output

## Landmark Data Format

Each of the 21 landmarks is represented as:
- **X coordinate**: 16-bit unsigned integer (0-65535)
- **Y coordinate**: 16-bit unsigned integer (0-65535)

### 336-bit Vector Structure
```
336-bit X vector:
[15:0]    = Landmark 0 X
[31:16]   = Landmark 1 X
[47:32]   = Landmark 2 X
...
[335:320] = Landmark 20 X

Same structure for Y vector
```

## Example: Adding Your Hand Pose Data

If you have extracted landmark coordinates like:
```
Landmark 0: x=1234, y=5678
Landmark 1: x=2345, y=6789
Landmark 2: x=3456, y=7890
...
(21 total landmarks)
```

### Step 1: Create landmark file (`my_landmarks.json`)
```json
{
  "landmarks": [
    [1234, 5678],
    [2345, 6789],
    [3456, 7890],
    [4567, 8901],
    [5678, 9012],
    [6789, 890],
    [7890, 1234],
    [8901, 2345],
    [9012, 3456],
    [1111, 4567],
    [2222, 5678],
    [3333, 6789],
    [4444, 7890],
    [5555, 8901],
    [6666, 9012],
    [7777, 890],
    [8888, 1111],
    [9999, 2222],
    [1000, 3333],
    [2000, 4444],
    [3000, 5555]
  ]
}
```

### Step 2: Run conversion script
```bash
python3 convert_landmarks.py my_landmarks.json output.verilog
```

### Step 3: Copy output into testbench
Open `output.verilog` and copy the generated `send_frame()` call into TEST CASE 4 of `tb_gesture_system_full.v`.

### Step 4: Run simulation
```bash
xvlog tb_gesture_system_full.v ../rtl/*.v
xsim tb_gesture_system_full -gui
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "frame_ready never asserts" | Check UART baud rate configuration (BR_LIMIT=27 for 50MHz) |
| "Landmarks not assembled correctly" | Verify coordinate format (16-bit unsigned) |
| "Gesture ID always 0" | Check that all 21 landmarks were received |
| "Simulation too slow" | Use direct `send_frame()` instead of UART (faster) |

## Gesture IDs

| ID | Gesture |
|----|---------|
| 0 | Open Palm |
| 1 | Pinch |
| 2 | Fist |
| 3-7 | Reserved |

## Files

- **tb_gesture_system_full.v** - Main testbench (edit TEST CASE 4 here)
- **convert_landmarks.py** - Helper script to convert coordinate data
- **tb_gesture_system_full.vcd** - Generated waveform file (view in GTKWave or similar)

## Notes

- Simulation uses 50 MHz clock (20 ns period)
- UART baud rate: ~115200 (50MHz with BR_LIMIT=27)
- Gesture classification latency: ~20 clock cycles per frame
- Frame assembly latency: variable (depends on UART timing)

---

**Ready to test?** Start with TEST CASE 1 (UART) or directly inject your landmarks using the conversion script!
