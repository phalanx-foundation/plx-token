import "@acton/env"
import "@acton/io"
import "@acton/emulation/scripts"
import "utils/common"

// Phase 2 companion — documents buyback burn after swap.
// Actual Ston.fi swap is handled by scripts/buyback-swap-burn.py (queue processor).

fun main() {
    val amount = env<coins>("PLX_BURN_AMOUNT")!;
    println("[buyback-swap-burn] PLX_BURN_AMOUNT={} (invoke buyback-burn after Ston.fi swap)", amount);
    println("[buyback-swap-burn] run: acton script scripts/buyback-burn.tolk --net mainnet");
}
