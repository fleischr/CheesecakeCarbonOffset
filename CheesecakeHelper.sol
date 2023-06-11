// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./CheesecakeHelperStorage.sol";
import "./interfaces/IToucanPoolToken.sol";
import "./interfaces/IToucanCarbonOffsets.sol";
import "./interfaces/IToucanContractRegistry.sol";

/**
 * @title Cheesecake CO2 Offset Helpers
 * @notice Helper functions that test the carbon offsetting (retirement)
 * process with fake Cheesecake Factory giftcards on the Celo testnet. Not for production use! Demo only!
 *
*/

contract CheescakeHelper is CheesecakeHelperStorage {
    using SafeERC20 for IERC20;

    event LogErrorString(string message);
    event LowLevelError(bytes data);

    constructor(
        string[] memory _eligibleTokenSymbols,
        address[] memory _eligibleTokenAddresses
    ) {
        uint256 i = 0;
        uint256 eligibleTokenSymbolsLen = _eligibleTokenSymbols.length;
        while (i < eligibleTokenSymbolsLen) {
            eligibleTokenAddresses[
                _eligibleTokenSymbols[i]
            ] = _eligibleTokenAddresses[i];
            i += 1;
        }
    }


        /**
     * @notice Emitted upon successful redemption of TCO2 tokens from a Toucan
     * pool token such as BCT or NCT.
     *
     * @param who The sender of the transaction
     * @param poolToken The address of the Toucan pool token used in the
     * redemption, for example, NCT or BCT
     * @param tco2s An array of the TCO2 addresses that were redeemed
     * @param amounts An array of the amounts of each TCO2 that were redeemed
     */
    event Redeemed(
        address who,
        address poolToken,
        address[] tco2s,
        uint256[] amounts
    );

    modifier onlyRedeemable(address _token) {
        require(isRedeemable(_token), "Token not redeemable");

        _;
    }

    modifier onlySwappable(address _token) {
        require(isSwappable(_token), "Token not swappable");

        _;
    }

   /**
     * @notice Checks whether an address can be used by the contract.
     * @param _erc20Address address of the ERC20 token to be checked
     * @return True if the address can be used by the contract
     */
    function isEligible(address _erc20Address) private view returns (bool) {
        bool isToucanContract = IToucanContractRegistry(contractRegistryAddress)
            .checkERC20(_erc20Address);
        if (isToucanContract) return true;
        if (_erc20Address == eligibleTokenAddresses["BCT"]) return true;
        if (_erc20Address == eligibleTokenAddresses["NCT"]) return true;
        if (_erc20Address == eligibleTokenAddresses["chUSD"]) return true;
        if (_erc20Address == eligibleTokenAddresses["chCO2"]) return true;
        if (_erc20Address == eligibleTokenAddresses["WCELO"]) return true;
        return false;
    }

    /**
     * @notice Checks whether an address can be used in a token swap
     * @param _erc20Address address of token to be checked
     * @return True if the specified address can be used in a swap
     */
    function isSwappable(address _erc20Address) private view returns (bool) {
        if (_erc20Address == eligibleTokenAddresses["chUSD"]) return true;
        if (_erc20Address == eligibleTokenAddresses["chCO2"]) return true;
        if (_erc20Address == eligibleTokenAddresses["CELO"]) return true;
        return false;
    }


        /**
     * @notice Checks whether an address is a Toucan pool token address
     * @param _erc20Address address of token to be checked
     * @return True if the address is a Toucan pool token address
     */
    function isRedeemable(address _erc20Address) private view returns (bool) {
        if (_erc20Address == eligibleTokenAddresses["BCT"]) return true;
        if (_erc20Address == eligibleTokenAddresses["NCT"]) return true;
        return false;
    }

    function autoOffsetExactOutToken(
        address _depositedToken,
        address _poolToken,
        uint256 _amountToOffset
    ) public returns (address[] memory tco2s, uint256[] memory amounts) {
        // swap input token for BCT / NCT
        swapExactOutToken(_depositedToken, _poolToken, _amountToOffset);

        // redeem BCT / NCT for TCO2s
        (tco2s, amounts) = autoRedeem(_poolToken, _amountToOffset);

        // retire the TCO2s to achieve offset
        autoRetire(tco2s, amounts);
    }

    function autoOffsetExactInToken(
        address _fromToken,
        uint256 _amountToSwap,
        address _poolToken
    ) public returns (address[] memory tco2s, uint256[] memory amounts) {
        // swap input token for BCT / NCT
        uint256 amountToOffset = swapExactInToken(_fromToken, _amountToSwap, _poolToken);

        // redeem BCT / NCT for TCO2s
        (tco2s, amounts) = autoRedeem(_poolToken, amountToOffset);

        // retire the TCO2s to achieve offset
        autoRetire(tco2s, amounts);
    }

    function autoOffsetExactOutETH(address _poolToken, uint256 _amountToOffset)
        public
        payable
        returns (address[] memory tco2s, uint256[] memory amounts) {
        // swap MATIC for BCT / NCT
        swapExactOutETH(_poolToken, _amountToOffset);

        // redeem BCT / NCT for TCO2s
        (tco2s, amounts) = autoRedeem(_poolToken, _amountToOffset);

        // retire the TCO2s to achieve offset
        autoRetire(tco2s, amounts);
    }

    function autoOffsetExactInETH(address _poolToken)
        public
        payable
        returns (address[] memory tco2s, uint256[] memory amounts)
    {
        // swap MATIC for BCT / NCT
        uint256 amountToOffset = swapExactInETH(_poolToken);

        // redeem BCT / NCT for TCO2s
        (tco2s, amounts) = autoRedeem(_poolToken, amountToOffset);

        // retire the TCO2s to achieve offset
        autoRetire(tco2s, amounts);
    }

    function autoOffsetPoolToken(
        address _poolToken,
        uint256 _amountToOffset
    ) public returns (address[] memory tco2s, uint256[] memory amounts) {
        // deposit pool token from user to this contract
        deposit(_poolToken, _amountToOffset);

        // redeem BCT / NCT for TCO2s
        (tco2s, amounts) = autoRedeem(_poolToken, _amountToOffset);

        // retire the TCO2s to achieve offset
        autoRetire(tco2s, amounts);
    }

    function autoRetire(address[] memory _tco2s, uint256[] memory _amounts)
        public {
        uint256 tco2sLen = _tco2s.length;
        require(tco2sLen != 0, "Array empty");

        require(tco2sLen == _amounts.length, "Arrays unequal");

        uint256 i = 0;
        while (i < tco2sLen) {
            if (_amounts[i] == 0) {
                unchecked {
                    i++;
                }
                continue;
            }
            require(
                balances[msg.sender][_tco2s[i]] >= _amounts[i],
                "Insufficient TCO2 balance"
            );

            balances[msg.sender][_tco2s[i]] -= _amounts[i];

            try IToucanCarbonOffsets(_tco2s[i]).retire(_amounts[i]) {
                emit LogErrorString("retired tco2 with cheesecake. nice!");
            } catch Error(string memory reason) {
                emit LogErrorString(reason);
            } catch (bytes memory reason) {
                emit LowLevelError(reason);
            }

            unchecked {
                ++i;
            }
        }
    }

    function autoRedeem(address _fromToken, uint256 _amount)
        public
        onlyRedeemable(_fromToken)
        returns (address[] memory tco2s, uint256[] memory amounts) {
        require(
            balances[msg.sender][_fromToken] >= _amount,
            "Insufficient NCT/BCT balance"
        );

        // instantiate pool token (NCT or BCT)
        IToucanPoolToken PoolTokenImplementation = IToucanPoolToken(_fromToken);

        // auto redeem pool token for TCO2; will transfer automatically picked TCO2 to this contract
        (tco2s, amounts) = PoolTokenImplementation.redeemAuto2(_amount);

        // update balances
        balances[msg.sender][_fromToken] -= _amount;
        uint256 tco2sLen = tco2s.length;
        for (uint256 index = 0; index < tco2sLen; index++) {
            balances[msg.sender][tco2s[index]] += amounts[index];
        }

        emit Redeemed(msg.sender, _fromToken, tco2s, amounts);
    }

    function routerSushi() internal view returns (IUniswapV2Router02) {
        return IUniswapV2Router02(sushiRouterAddress);
    }

    function calculateExactOutSwap(
        address _fromToken,
        address _toToken,
        uint256 _toAmount)
        internal view
        returns (address[] memory path, uint256[] memory amounts)
    {
        path = generatePath(_fromToken, _toToken);
        uint256 len = path.length;

        amounts = routerSushi().getAmountsIn(_toAmount, path);

        // sanity check arrays
        require(len == amounts.length, "Arrays unequal");
        require(_toAmount == amounts[len - 1], "Output amount mismatch");
    }

    function calculateExactInSwap(
        address _fromToken,
        uint256 _fromAmount,
        address _toToken)
        internal view
        returns (address[] memory path, uint256[] memory amounts)
    {
        path = generatePath(_fromToken, _toToken);
        uint256 len = path.length;

        amounts = routerSushi().getAmountsOut(_fromAmount, path);

        // sanity check arrays
        require(len == amounts.length, "Arrays unequal");
        require(_fromAmount == amounts[0], "Input amount mismatch");
    }

    function generatePath(address _fromToken, address _toToken)
        internal
        view
        returns (address[] memory) {
        if (_fromToken == eligibleTokenAddresses["chUSD"]) {
            address[] memory path = new address[](2);
            path[0] = _fromToken;
            path[1] = _toToken;
            return path;
        } else {
            address[] memory path = new address[](3);
            path[0] = _fromToken;
            path[1] = eligibleTokenAddresses["chUSD"];
            path[2] = _toToken;
            return path;
        }
    }

    /**
     * @notice Allow users to withdraw tokens they have deposited.
     */
    function withdraw(address _erc20Addr, uint256 _amount) public {
        require(
            balances[msg.sender][_erc20Addr] >= _amount,
            "Insufficient balance"
        );

        IERC20(_erc20Addr).safeTransfer(msg.sender, _amount);
        balances[msg.sender][_erc20Addr] -= _amount;
    }

    /**
     * @notice Allow users to deposit BCT / NCT.
     * @dev Needs to be approved
     */
    function deposit(address _erc20Addr, uint256 _amount) public onlyRedeemable(_erc20Addr) {
        IERC20(_erc20Addr).safeTransferFrom(msg.sender, address(this), _amount);
        balances[msg.sender][_erc20Addr] += _amount;
    }

    /**
     * @notice Swap eligible ERC20 tokens for Toucan pool tokens (BCT/NCT) on SushiSwap
     * @dev Needs to be approved on the client side
     * @param _fromToken The ERC20 oken to deposit and swap
     * @param _toToken The token to swap for (will be held within contract)
     * @param _toAmount The required amount of the Toucan pool token (NCT/BCT)
     */
    function swapExactOutToken(
        address _fromToken,
        address _toToken,
        uint256 _toAmount
    ) public onlySwappable(_fromToken) onlyRedeemable(_toToken) {
        // calculate path & amounts
        (address[] memory path, uint256[] memory expAmounts) =
            calculateExactOutSwap(_fromToken, _toToken, _toAmount);
        uint256 amountIn = expAmounts[0];

        // transfer tokens
        IERC20(_fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            amountIn
        );

        // approve router
        IERC20(_fromToken).approve(sushiRouterAddress, amountIn);

        // swap
        uint256[] memory amounts = routerSushi().swapTokensForExactTokens(
            _toAmount,
            amountIn, // max. input amount
            path,
            address(this),
            block.timestamp
        );

        // remove remaining approval if less input token was consumed
        if (amounts[0] < amountIn) {
            IERC20(_fromToken).approve(sushiRouterAddress, 0);
        }

        // update balances
        balances[msg.sender][_toToken] += _toAmount;
    }

    /**
     * @notice Swap eligible ERC20 tokens for Toucan pool tokens (BCT/NCT) on
     * SushiSwap. All provided ERC20 tokens will be swapped.
     * @dev Needs to be approved on the client side.
     * @param _fromToken The ERC20 token to deposit and swap
     * @param _fromAmount The amount of ERC20 token to swap
     * @param _toToken The Toucan token to swap for (will be held within contract)
     * @return Resulting amount of Toucan pool token that got acquired for the
     * swapped ERC20 tokens.
     */
    function swapExactInToken(
        address _fromToken,
        uint256 _fromAmount,
        address _toToken
    ) public onlySwappable(_fromToken) onlyRedeemable(_toToken) returns (uint256) {
        // calculate path & amounts
        address[] memory path = generatePath(_fromToken, _toToken);
        uint256 len = path.length;

        // transfer tokens
        IERC20(_fromToken).safeTransferFrom(
            msg.sender,
            address(this),
            _fromAmount
        );

        // approve router
        IERC20(_fromToken).safeApprove(sushiRouterAddress, _fromAmount);

        // swap
        uint256[] memory amounts = routerSushi().swapExactTokensForTokens(
            _fromAmount,
            0, // min. output amount
            path,
            address(this),
            block.timestamp
        );
        uint256 amountOut = amounts[len - 1];

        // update balances
        balances[msg.sender][_toToken] += amountOut;

        return amountOut;
    }

    // apparently I need a fallback and a receive method to fix the situation where transfering dust MATIC
    // in the MATIC to token swap fails
    fallback() external payable {}

    receive() external payable {}

    /**
     * @notice Return how much MATIC is required in order to swap for the
     * desired amount of a Toucan pool token, for example, BCT or NCT.
     *
     * @param _toToken The address of the pool token to swap for, for
     * example, NCT or BCT
     * @param _toAmount The desired amount of pool token to receive
     * @return amounts The amount of MATIC required in order to swap for
     * the specified amount of the pool token
     */
    function calculateNeededETHAmount(address _toToken, uint256 _toAmount)
        public
        view
        onlyRedeemable(_toToken)
        returns (uint256)
    {
        address fromToken = eligibleTokenAddresses["WCELO"];
        (, uint256[] memory amounts) =
            calculateExactOutSwap(fromToken, _toToken, _toAmount);
        return amounts[0];
    }

    /**
     * @notice Calculates the expected amount of Toucan Pool token that can be
     * acquired by swapping the provided amount of MATIC.
     *
     * @param _fromMaticAmount The amount of MATIC to swap
     * @param _toToken The address of the pool token to swap for,
     * for example, NCT or BCT
     * @return The expected amount of Pool token that can be acquired
     */
    function calculateExpectedPoolTokenForETH(
        uint256 _fromMaticAmount,
        address _toToken
    ) public view onlyRedeemable(_toToken) returns (uint256) {
        address fromToken = eligibleTokenAddresses["WCELO"];
        (, uint256[] memory amounts) =
            calculateExactInSwap(fromToken, _fromMaticAmount, _toToken);
        return amounts[amounts.length - 1];
    }

    /**
     * @notice Swap MATIC for Toucan pool tokens (BCT/NCT) on SushiSwap.
     * Remaining MATIC that was not consumed by the swap is returned.
     * @param _toToken Token to swap for (will be held within contract)
     * @param _toAmount Amount of NCT / BCT wanted
     */
    function swapExactOutETH(address _toToken, uint256 _toAmount) public payable onlyRedeemable(_toToken) {
        // calculate path & amounts
        address fromToken = eligibleTokenAddresses["WCELO"];
        address[] memory path = generatePath(fromToken, _toToken);

        // swap
        uint256[] memory amounts = routerSushi().swapETHForExactTokens{
            value: msg.value
        }(_toAmount, path, address(this), block.timestamp);

        // send surplus back
        if (msg.value > amounts[0]) {
            uint256 leftoverETH = msg.value - amounts[0];
            (bool success, ) = msg.sender.call{value: leftoverETH}(
                new bytes(0)
            );

            require(success, "Failed to send surplus back");
        }

        // update balances
        balances[msg.sender][_toToken] += _toAmount;
    }

    /**
     * @notice Swap MATIC for Toucan pool tokens (BCT/NCT) on SushiSwap. All
     * provided MATIC will be swapped.
     * @param _toToken Token to swap for (will be held within contract)
     * @return Resulting amount of Toucan pool token that got acquired for the
     * swapped MATIC.
     */
    function swapExactInETH(address _toToken) public payable onlyRedeemable(_toToken) returns (uint256) {
        // calculate path & amounts
        uint256 fromAmount = msg.value;
        address fromToken = eligibleTokenAddresses["WCELO"];
        address[] memory path = generatePath(fromToken, _toToken);
        uint256 len = path.length;

        // swap
        uint256[] memory amounts = routerSushi().swapExactETHForTokens{
            value: fromAmount
        }(0, path, address(this), block.timestamp);
        uint256 amountOut = amounts[len - 1];

        // update balances
        balances[msg.sender][_toToken] += amountOut;

        return amountOut;
    }


}