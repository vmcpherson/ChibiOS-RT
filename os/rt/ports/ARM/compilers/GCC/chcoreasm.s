/*
    ChibiOS/RT - Copyright (C) 2006,2007,2008,2009,2010,
                 2011,2012,2013 Giovanni Di Sirio.

    This file is part of ChibiOS/RT.

    ChibiOS/RT is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    ChibiOS/RT is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/**
 * @file    ARM/compilers/GCC/chcoreasm.s
 * @brief   ARM architecture port low level code.
 *
 * @addtogroup ARM_CORE
 * @{
 */

#include "chconf.h"

#define FALSE 0
#define TRUE 1

#if !defined(__DOXYGEN__)

                .set    MODE_USR, 0x10
                .set    MODE_FIQ, 0x11
                .set    MODE_IRQ, 0x12
                .set    MODE_SVC, 0x13
                .set    MODE_ABT, 0x17
                .set    MODE_UND, 0x1B
                .set    MODE_SYS, 0x1F

                .equ    I_BIT, 0x80
                .equ    F_BIT, 0x40

                .text

/*
 * Interrupt enable/disable functions, only present if there is THUMB code in
 * the system because those are inlined in ARM code.
 */
#if defined(THUMB_PRESENT)
                .balign 16
                .code   16
                .thumb_func
                .global _port_disable_thumb
_port_disable_thumb:
                mov     r3, pc
                bx      r3
.code 32
                mrs     r3, CPSR
                orr     r3, #I_BIT
                msr     CPSR_c, r3
                orr     r3, #F_BIT
                msr     CPSR_c, r3
                bx      lr

                .balign 16
                .code   16
                .thumb_func
                .global _port_suspend_thumb
_port_suspend_thumb:
                // Goes into _port_unlock_thumb

                .code   16
                .thumb_func
                .global _port_lock_thumb
_port_lock_thumb:
                mov     r3, pc
                bx      r3
                .code   32
                msr     CPSR_c, #MODE_SYS | I_BIT
                bx      lr

                .balign 16
                .code   16
                .thumb_func
                .global _port_enable_thumb
_port_enable_thumb:
                // Goes into _port_unlock_thumb

                .code   16
                .thumb_func
                .global _port_unlock_thumb
_port_unlock_thumb:
                mov     r3, pc
                bx      r3
                .code   32
                msr     CPSR_c, #MODE_SYS
                bx      lr
#endif /* defined(THUMB_PRESENT) */

                .balign 16
#if defined(THUMB_PRESENT)
                .code   16
                .thumb_func
                .global _port_switch_thumb
_port_switch_thumb:
                mov     r2, pc
                bx      r2
                // Goes into _port_switch_arm in ARM mode
#endif /* defined(THUMB_PRESENT) */

                .code   32
                .global _port_switch_arm
_port_switch_arm:
                stmfd   sp!, {r4, r5, r6, r7, r8, r9, r10, r11, lr}
                str     sp, [r1, #12]
                ldr     sp, [r0, #12]
#if defined(THUMB_PRESENT)
                ldmfd   sp!, {r4, r5, r6, r7, r8, r9, r10, r11, lr}
                bx      lr
#else /* !defined(THUMB_PRESENT)T */
                ldmfd   sp!, {r4, r5, r6, r7, r8, r9, r10, r11, pc}
#endif /* !defined(THUMB_PRESENT) */

/*
 * Common exit point for all IRQ routines, it performs the rescheduling if
 * required.
 * System stack frame structure after a context switch in the
 * interrupt handler:
 *
 * High +------------+
 *      |   LR_USR   | -+
 *      |     r12    |  |
 *      |     r3     |  |
 *      |     r2     |  | External context: IRQ handler frame
 *      |     r1     |  |
 *      |     r0     |  |
 *      |     PC     |  |   (user code return address)
 *      |   PSR_USR  | -+   (user code status)
 *      |    ....    | <- chSchDoReschedule() stack frame, optimize it for space
 *      |     LR     | -+   (system code return address)
 *      |     r11    |  |
 *      |     r10    |  |
 *      |     r9     |  |
 *      |     r8     |  | Internal context: chSysSwitch() frame
 *      |     r7     |  |
 *      |     r6     |  |
 *      |     r5     |  |
 * SP-> |     r4     | -+
 * Low  +------------+
 */
                .balign 16
#if defined(THUMB_NO_INTERWORKING)
                .code   16
                .thumb_func
                .globl  _port_irq_common
_port_irq_common:
                bl      chSchIsPreemptionRequired
                mov     lr, pc
                bx      lr
                .code   32

#else /* !defined(THUMB_NO_INTERWORKING) */
                .code   32
                .globl  _port_irq_common
_port_irq_common:
                bl      chSchIsPreemptionRequired
#endif /* !defined(THUMB_NO_INTERWORKING) */

                cmp     r0, #0                  // Simply returns if a
                ldmeqfd sp!, {r0-r3, r12, lr}   // reschedule is not
                subeqs  pc, lr, #4              // required.

                // Saves the IRQ mode registers in the system stack.
                ldmfd   sp!, {r0-r3, r12, lr}   // IRQ stack now empty.
                msr     CPSR_c, #MODE_SYS | I_BIT
                stmfd   sp!, {r0-r3, r12, lr}   // Registers on System Stack.
                msr     CPSR_c, #MODE_IRQ | I_BIT
                mrs     r0, SPSR
                mov     r1, lr
                msr     CPSR_c, #MODE_SYS | I_BIT
                stmfd   sp!, {r0, r1}           // Push R0=SPSR, R1=LR_IRQ.

                // Context switch.
#if defined(THUMB_NO_INTERWORKING)
                add     r0, pc, #1
                bx      r0
                .code   16
#if CH_DBG_SYSTEM_STATE_CHECK
                bl      dbg_check_lock
#endif
                bl      chSchDoReschedule
#if CH_DBG_SYSTEM_STATE_CHECK
                bl      dbg_check_unlock
#endif
                mov     lr, pc
                bx      lr
                .code   32
#else /* !defined(THUMB_NO_INTERWORKING) */
#if CH_DBG_SYSTEM_STATE_CHECK
                bl      dbg_check_lock
#endif
                bl      chSchDoReschedule
#if CH_DBG_SYSTEM_STATE_CHECK
                bl      dbg_check_unlock
#endif
#endif /* !defined(THUMB_NO_INTERWORKING) */

                // Re-establish the IRQ conditions again.
                ldmfd    sp!, {r0, r1}          // Pop R0=SPSR, R1=LR_IRQ.
                msr     CPSR_c, #MODE_IRQ | I_BIT
                msr     SPSR_fsxc, r0
                mov     lr, r1
                msr     CPSR_c, #MODE_SYS | I_BIT
                ldmfd   sp!, {r0-r3, r12, lr}
                msr     CPSR_c, #MODE_IRQ | I_BIT
                subs    pc, lr, #4

/*
 * Threads trampoline code.
 * NOTE: The threads always start in ARM mode and then switches to the
 * thread-function mode.
 */
                .balign 16
                .code   32
                .globl  _port_thread_start
_port_thread_start:
#if CH_DBG_SYSTEM_STATE_CHECK
                mov     r0, #0
                ldr     r1, =dbg_lock_cnt
                str     r0, [r1]
#endif
                msr     CPSR_c, #MODE_SYS
#if defined(THUMB_NO_INTERWORKING)
                mov     r0, r5
                mov     lr, pc
                bx      r4
                bl      chThdExit
#else /* !defined(THUMB_NO_INTERWORKING) */
                add     r0, pc, #1
                bx      r0
                .code 16
                mov     r0, r5
                bl      jmpr4
                bl      chThdExit
jmpr4:
                bx      r4
#endif /* !defined(THUMB_NO_INTERWORKING) */

#endif /* !defined(__DOXYGEN__) */

/** @} */
