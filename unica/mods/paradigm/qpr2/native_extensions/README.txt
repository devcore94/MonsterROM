QPR2 native entry points naast de originele Samsung-Bionic

Bronnen voor een gewone libunica_qpr2_native.so, ARM32 en ARM64.
membarrier/execveat voeren de echte syscalls uit en behouden errno.
free_sized/free_aligned_sized gebruiken de oorspronkelijke allocator.
De Samsung property-area, inclusief de private Knox NAP-ABI, blijft bij
de oorspronkelijke provider. Geen gewone property-API-alias of successtub.

Bouwen: SourceBuilder --goal native. De libs zijn kandidaatuitvoer in
system/lib en system/lib64, buiten alle APEX'en. Er zijn nog geen bestaande
ROM-consumers automatisch naar deze provider omgelinkt. clone3 vereist de
bijpassende thread/TLS-implementatie en is niet door een raw syscall vervangen.
Deze bronmap voegt geen autonome framework- of firmware-implementatie toe.
