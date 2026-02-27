; =============================================================
; ProbablyFineOS — Round-Robin Scheduler
; Included into kernel/kernel.asm
;
; Implements:
; - Ready queue (linked list of READY threads)
; - schedule() - select next thread to run
; - Thread state transitions
; - Preemptive multitasking via timer integration
; =============================================================

; ==============================================================
; Ready queue (circular linked list)
; ==============================================================
ready_queue_head    dd 0        ; Pointer to first READY thread
ready_queue_tail    dd 0        ; Pointer to last READY thread

; ==============================================================
; scheduler_init — initialize scheduler
; Called after thread_init during kernel initialization
; ==============================================================
scheduler_init:
    ; Ready queue starts empty (idle thread will run if empty)
    mov     dword [ready_queue_head], 0
    mov     dword [ready_queue_tail], 0
    ret

; ==============================================================
; ready_queue_enqueue — add thread to end of ready queue
; Input: eax = pointer to TCB
; Clobbers: ebx, ecx
; ==============================================================
ready_queue_enqueue:
    push    ebx

    ; Set thread state to READY
    mov     dword [eax + TCB_STATE], THREAD_STATE_READY

    ; Clear next/prev pointers
    mov     dword [eax + TCB_NEXT], 0
    mov     dword [eax + TCB_PREV], 0

    ; Check if queue is empty
    mov     ebx, [ready_queue_tail]
    test    ebx, ebx
    jz      .empty_queue

    ; Queue not empty: add to tail
    mov     [ebx + TCB_NEXT], eax   ; old_tail.next = new_thread
    mov     [eax + TCB_PREV], ebx   ; new_thread.prev = old_tail
    mov     [ready_queue_tail], eax ; tail = new_thread
    jmp     .done

.empty_queue:
    ; Queue empty: this is first thread
    mov     [ready_queue_head], eax
    mov     [ready_queue_tail], eax

.done:
    pop     ebx
    ret

; ==============================================================
; ready_queue_dequeue — remove and return first thread from ready queue
; Returns: eax = pointer to TCB, or 0 if queue empty
; Clobbers: ebx
; ==============================================================
ready_queue_dequeue:
    push    ebx

    ; Get head of queue
    mov     eax, [ready_queue_head]
    test    eax, eax
    jz      .empty                  ; Queue empty

    ; Remove from queue
    mov     ebx, [eax + TCB_NEXT]   ; next thread
    mov     [ready_queue_head], ebx ; head = next

    ; Update next thread's prev pointer
    test    ebx, ebx
    jz      .last_thread
    mov     dword [ebx + TCB_PREV], 0
    jmp     .done

.last_thread:
    ; Was last thread in queue
    mov     dword [ready_queue_tail], 0

.done:
    ; Clear dequeued thread's linkage
    mov     dword [eax + TCB_NEXT], 0
    mov     dword [eax + TCB_PREV], 0

.empty:
    pop     ebx
    ret

; ==============================================================
; schedule — select next thread to run (round-robin)
; Returns: eax = pointer to next TCB to run
; Never returns NULL (returns idle thread if no ready threads)
; ==============================================================
schedule:
    push    ebx

    ; Try to get next READY thread from queue
    call    ready_queue_dequeue
    test    eax, eax
    jnz     .found

    ; No ready threads: return idle thread (TID 0)
    lea     eax, [thread_table]     ; Idle thread is first TCB
    jmp     .done

.found:
    ; Set thread state to RUNNING
    mov     dword [eax + TCB_STATE], THREAD_STATE_RUNNING

.done:
    pop     ebx
    ret

; ==============================================================
; scheduler_tick — called from timer_tick on each timer interrupt
; Implements preemptive multitasking by checking quantum expiration
; ==============================================================
scheduler_tick:
    push    eax
    push    ebx
    push    ecx

    ; Get current thread
    mov     eax, [current_thread]
    test    eax, eax
    jz      .boot_context           ; NULL = boot context (before first thread)

    ; Check if current thread is idle (TID 0)
    cmp     dword [eax + TCB_TID], 0
    je      .check_ready            ; Idle thread: check if others ready

    ; Decrement quantum
    mov     ecx, [eax + TCB_QUANTUM]
    test    ecx, ecx
    jz      .quantum_expired        ; Already 0, expire
    dec     ecx
    mov     [eax + TCB_QUANTUM], ecx
    test    ecx, ecx
    jnz     .done                   ; Quantum not expired yet

.quantum_expired:
    ; Quantum expired: preempt current thread
    ; Save current thread (move to READY if not idle)
    mov     ebx, eax                ; Save current thread
    cmp     dword [ebx + TCB_TID], 0
    je      .switch                 ; Don't enqueue idle thread

    ; Add current thread to ready queue
    mov     eax, ebx
    call    ready_queue_enqueue

.switch:
    ; Select next thread
    call    schedule
    mov     ecx, eax                ; New thread in ECX

    ; Check if new thread is same as current
    cmp     ecx, ebx
    je      .done                   ; Same thread, no switch needed

    ; Perform context switch
    mov     eax, ebx                ; Old thread
    mov     ebx, ecx                ; New thread
    call    context_switch          ; Switch!

    ; Note: After context_switch, we're running in new thread context
    ; and will return to wherever that thread was interrupted

.done:
    pop     ecx
    pop     ebx
    pop     eax
    ret

.check_ready:
    ; Idle thread is running: check if any threads are ready
    mov     eax, [ready_queue_head]
    test    eax, eax
    jz      .done                   ; No ready threads, stay in idle

    ; Ready thread available: switch from idle
    mov     ebx, [current_thread]   ; Current (idle)
    call    schedule                ; Get next thread
    mov     ecx, eax                ; New thread
    mov     eax, ebx                ; Old thread (idle)
    mov     ebx, ecx                ; New thread
    call    context_switch          ; Switch to ready thread
    jmp     .done

.boot_context:
    ; We're in boot context (current_thread == NULL)
    ; This happens before any threads are created
    ; Check if any threads are ready to run
    mov     eax, [ready_queue_head]
    test    eax, eax
    jnz     .first_switch           ; Ready threads exist, do first switch

    ; No ready threads: check if we need to switch to idle
    ; For now, just stay in boot context
    jmp     .done

.first_switch:
    ; First context switch from boot context to a thread
    call    schedule                ; Get next thread (or idle if none)
    mov     ebx, eax                ; New thread
    xor     eax, eax                ; Old thread = NULL (boot context)
    call    context_switch          ; Switch!
    jmp     .done
