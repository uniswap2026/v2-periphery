pragma solidity =0.6.6;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)
// 溢出安全数学库，源自DappHub，提供安全的算术运算

library SafeMath {
    /// @dev 安全加法：确保加法运算不会溢出
    /// @param x 第一个加数
    /// @param y 第二个加数
    /// @return z 加法结果
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    /// @dev 安全减法：确保减法运算不会下溢
    /// @param x 被减数
    /// @param y 减数
    /// @return z 减法结果
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    /// @dev 安全乘法：确保乘法运算不会溢出
    /// @param x 第一个乘数
    /// @param y 第二个乘数
    /// @return z 乘法结果
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}
