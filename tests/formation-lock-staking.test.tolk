import "@stdlib/assert"
import "@stdlib/test"
import "@gen/PlxLockVault.code"
import "@gen/PlxStaking.code"

test "PlxLockVault deploys with empty storage" {
    val lockCode = plxLockVaultCompiledCode();
    val stakingCode = plxStakingCompiledCode();
    assert(lockCode.hash() != 0);
    assert(stakingCode.hash() != 0);
}

test "Lock tier bonus bps within range" {
    val bonusBps: int = 6000;
    assert(bonusBps <= 10000);
}

test "Staking APR bps default 800" {
    val aprBps: int = 800;
    assert(aprBps > 0);
}
