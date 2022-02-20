// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface ICamelit {
    struct CamelBandit {
        bool isCamel;
        // Make sure 0 always mean no trait
        uint8 background;
        uint8 eyesOrTree;
        uint8 faceOrNeck;
        uint8 weaponsOrHead;
        uint8 companionsOrBack;
        uint8 nullOrSmokingStuff;

    }
    function getPaidTokens() external view returns (uint256);
    function getTokenTraits(uint256 tokenId) external view returns (CamelBandit memory);
}