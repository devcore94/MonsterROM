/* SPDX-License-Identifier: GPL-3.0-or-later
 * SDK36 -> One UI 9 AudioTrack::set adapter for Samsung's SMPS provider.
 * See README.md for the shipped-artifact ABI and codecProvenance evidence.
 * All original arguments (including s0/maxRequiredSpeed), attribution and
 * the real status_t result pass through unchanged. This is NOT a JNI stub.
 */
#define OLD_SET _ZN7android10AudioTrack3setE19audio_stream_type_tj14audio_format_t20audio_channel_mask_tm20audio_output_flags_tRKNS_2wpINS0_19IAudioTrackCallbackEEEiRKNS_2spINS_7IMemoryEEEb15audio_session_tNS0_13transfer_typeEPK20audio_offload_info_tRKNS_7content22AttributionSourceStateEPK18audio_attributes_tbfi
#define NEW_SET _ZN7android10AudioTrack3setE19audio_stream_type_tj14audio_format_t20audio_channel_mask_tm20audio_output_flags_tRKNS_2wpINS0_19IAudioTrackCallbackEEEiRKNS_2spINS_7IMemoryEEEb15audio_session_tNS0_13transfer_typeEPK20audio_offload_info_tRKNS_7content22AttributionSourceStateEPK18audio_attributes_tbfiRKNSt3__112basic_stringIcNSR_11char_traitsIcEENSR_9allocatorIcEEEE

.text
.p2align 2
.global OLD_SET
.type OLD_SET, %function
OLD_SET:
    .cfi_startproc
    bti c
    paciasp
    .cfi_negate_ra_state
    sub sp, sp, #112
    .cfi_def_cfa_offset 112
    stp x29, x30, [sp, #96]
    .cfi_offset x29, -16
    .cfi_offset x30, -8
    add x29, sp, #96

    /* AAPCS64: ten original stack slots, x0..x7 and s0 untouched. */
    ldp x8, x9, [sp, #112]
    stp x8, x9, [sp]
    ldp x8, x9, [sp, #128]
    stp x8, x9, [sp, #16]
    ldp x8, x9, [sp, #144]
    stp x8, x9, [sp, #32]
    ldp x8, x9, [sp, #160]
    stp x8, x9, [sp, #48]
    ldp x8, x9, [sp, #176]
    stp x8, x9, [sp, #64]
    adrp x8, .Lempty_codec_provenance
    add x8, x8, :lo12:.Lempty_codec_provenance
    str x8, [sp, #80]
    bl NEW_SET

    ldp x29, x30, [sp, #96]
    add sp, sp, #112
    .cfi_def_cfa_offset 0
    autiasp
    .cfi_negate_ra_state
    ret
    .cfi_endproc
.size OLD_SET, .-OLD_SET

.section .rodata,"a",%progbits
.p2align 3
.Lempty_codec_provenance:
    /* One UI 9 libc++'s 24-byte empty short string, as used by ToneGenerator.
     * SMPS produces PCM itself, not decoded media: no codec provenance.
     */
    .zero 24

.section .note.gnu.property,"a",%note
.p2align 3
    .long 4, 16, 5
    .asciz "GNU"
    .long 0xc0000000, 4, 3 /* GNU_PROPERTY_AARCH64_FEATURE_1_AND: BTI | PAC */
    .long 0
.section .note.GNU-stack,"",%progbits
