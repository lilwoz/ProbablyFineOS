## ADDED Requirements

### Requirement: Video Driver Module Isolation
The video driver SHALL reside entirely in a dedicated FASM include file (`video.asm`) and expose no internal labels to other kernel subsystems. All cross-subsystem interaction SHALL occur exclusively through the public `video_*` procedure labels and named equates defined in `video.asm`.

#### Scenario: Kernel includes video module
- **WHEN** `kernel.asm` assembles with `include 'video.asm'`
- **THEN** all `video_*` labels and equates are available to `kernel.asm` with no unresolved symbol errors

#### Scenario: No internal label leakage
- **WHEN** any label inside `video.asm` is prefixed with a dot (`.`) or is not explicitly listed in the public API
- **THEN** it SHALL NOT be callable or referenceable from outside `video.asm`

---

### Requirement: VESA VBE 2.0 Mode Negotiation
The video driver SHALL query the VESA VBE controller information block (INT 0x10/AX=0x4F00) and enumerate available modes (INT 0x10/AX=0x4F01) to select the best supported video mode from the following priority list, in order:
1. 1024×768, 32 bpp, linear framebuffer
2. 800×600, 32 bpp, linear framebuffer
3. 800×600, 16 bpp, linear framebuffer
4. 640×480, 32 bpp, linear framebuffer
5. 640×480, 8 bpp, bank-switched (legacy fallback)

The driver SHALL set the selected mode via INT 0x10/AX=0x4F02 and store the active resolution, bits-per-pixel, and physical framebuffer address in module-private variables accessible to drawing routines.

#### Scenario: VBE 2.0 preferred mode available
- **WHEN** `video_init` is called and the VBE controller reports mode 800×600×32bpp with a linear framebuffer
- **THEN** that mode is set, `video_active_width` = 800, `video_active_height` = 600, `video_active_bpp` = 32, and CF is clear on return

#### Scenario: All linear modes unavailable — fallback to bank-switched
- **WHEN** `video_init` is called and no VBE 2.0 linear mode from the priority list is reported by the controller
- **THEN** the driver sets 640×480×8bpp bank-switched mode, `video_active_width` = 640, `video_active_height` = 480, `video_active_bpp` = 8, and CF is clear on return

#### Scenario: VBE controller absent or reports failure
- **WHEN** INT 0x10/AX=0x4F00 returns AX ≠ 0x004F or the signature field is not `VESA`
- **THEN** `video_init` sets CF and returns without altering the video mode

---

### Requirement: Unreal Mode Linear Framebuffer Access
When a VBE 2.0 linear framebuffer mode is selected, the driver SHALL activate unreal mode (big real mode) once during `video_init` so that subsequent drawing routines can address the full 32-bit physical framebuffer address space using the `ES` segment with the `a32` address-size prefix, without permanently leaving 16-bit real mode.

#### Scenario: Unreal mode activated at init
- **WHEN** `video_init` succeeds with a linear framebuffer mode
- **THEN** `video_enter_unreal` has been called, `ES` holds a flat 4 GB descriptor, and the CPU is in 16-bit real mode (BIOS interrupts remain functional)

#### Scenario: Pixel write reaches high physical address
- **WHEN** `video_put_pixel` is called with coordinates whose framebuffer offset exceeds 0xFFFF
- **THEN** the pixel is written correctly to the physical address without a bank-switch call or address wrap-around

#### Scenario: BIOS calls still functional after unreal mode
- **WHEN** any BIOS interrupt (e.g., INT 0x16 for keyboard) is invoked after `video_enter_unreal`
- **THEN** the interrupt completes normally and ES flat limit is restored if it was disturbed

---

### Requirement: Drawing Primitive API
The video driver SHALL expose the following callable procedures. All procedures SHALL preserve all general-purpose registers (via `pusha`/`popa`). Parameters are passed in registers as documented. CF SHALL be set on any invalid input; otherwise CF is clear.

| Procedure | Parameters | Action |
|---|---|---|
| `video_init` | none | Negotiate mode, activate framebuffer |
| `video_clear` | `eax` = 32-bit color | Fill entire framebuffer |
| `video_put_pixel` | `cx` = x, `dx` = y, `eax` = color | Write single pixel |
| `video_draw_hline` | `cx` = x0, `dx` = y, `si` = x1, `eax` = color | Draw horizontal line |
| `video_draw_vline` | `cx` = x, `dx` = y0, `si` = y1, `eax` = color | Draw vertical line |
| `video_draw_rect` | `cx` = x, `dx` = y, `si` = w, `di` = h, `eax` = color | Draw rectangle outline |
| `video_fill_rect` | `cx` = x, `dx` = y, `si` = w, `di` = h, `eax` = color | Draw filled rectangle |

#### Scenario: Put pixel within bounds
- **WHEN** `video_put_pixel` is called with x < `video_active_width` and y < `video_active_height`
- **THEN** exactly one pixel at that coordinate is updated and CF is clear on return

#### Scenario: Put pixel out of bounds is clipped
- **WHEN** `video_put_pixel` is called with x ≥ `video_active_width` or y ≥ `video_active_height`
- **THEN** no memory is written and CF is set on return

#### Scenario: Fill rect covers correct region
- **WHEN** `video_fill_rect` is called with x=10, y=20, w=100, h=50 at 32bpp
- **THEN** pixels at rows 20–69 and columns 10–109 are set to the given color and no pixel outside that rectangle is modified

#### Scenario: Register preservation
- **WHEN** any `video_*` procedure is called
- **THEN** all general-purpose registers (`ax`, `bx`, `cx`, `dx`, `si`, `di`, `bp`, `sp`) have the same values after the call as before it

---

### Requirement: Resolution and Color Depth Equates
The video driver SHALL define the following FASM equates, set at assembly time to the compile-time maximum supported values, so that kernel subsystems may use symbolic constants instead of hardcoded numbers:

- `VIDEO_MAX_WIDTH` — horizontal pixel count of the preferred/target mode
- `VIDEO_MAX_HEIGHT` — vertical pixel count of the preferred/target mode
- `VIDEO_BPP` — bits per pixel of the preferred/target mode

#### Scenario: Equates usable in kernel.asm
- **WHEN** `kernel.asm` references `VIDEO_MAX_WIDTH` after including `video.asm`
- **THEN** the assembler substitutes the correct numeric value without error

#### Scenario: No magic numbers in kernel.asm for resolution
- **WHEN** `kernel.asm` is assembled
- **THEN** the literals `640` and `480` do not appear in video-related address calculations; they are replaced by `VIDEO_MAX_WIDTH` and `VIDEO_MAX_HEIGHT`
