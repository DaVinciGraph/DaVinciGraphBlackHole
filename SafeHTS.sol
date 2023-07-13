// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./IHederaTokenService.sol";
import "./HederaResponseCodes.sol";

library SafeHTS {
    address internal constant precompileAddress = address(0x167);
    // 90 days in seconds
    int32 internal constant defaultAutoRenewPeriod = 7776000;

    error SingleAssociationFailed();
    error TokenTransferFailed();
    error GetTokenInfoFailed();
    error GetTokenCustomFeesFailed();
    error GetTokenTypeFailed();

    function safeAssociateToken(address token, address account) internal {
        (bool success, bytes memory result) = precompileAddress.call(abi.encodeWithSelector(IHederaTokenService.associateToken.selector, account, token));
        if (!tryDecodeSuccessResponseCode(success, result)) revert SingleAssociationFailed();
    }

    function safeTransferToken(address token, address sender, address receiver, int64 amount) internal {
        (bool success, bytes memory result) = precompileAddress.call(abi.encodeWithSelector( IHederaTokenService.transferToken.selector, token, sender, receiver, amount));
        if (!tryDecodeSuccessResponseCode(success, result)) revert TokenTransferFailed();
    }

    function safeGetTokenType(address token) internal returns (int32 tokenType) {
        int32 responseCode;
        (bool success, bytes memory result) = precompileAddress.call(abi.encodeWithSelector( IHederaTokenService.getTokenType.selector, token));
        (responseCode, tokenType) = success ? abi.decode(result, (int32, int32)) : (HederaResponseCodes.UNKNOWN, int32(0));
        if (responseCode != HederaResponseCodes.SUCCESS) revert GetTokenTypeFailed();
    }

    function tryDecodeSuccessResponseCode(bool success, bytes memory result) private pure returns (bool) {
        return (success ? abi.decode(result, (int32)) : HederaResponseCodes.UNKNOWN) == HederaResponseCodes.SUCCESS;
    }
}
