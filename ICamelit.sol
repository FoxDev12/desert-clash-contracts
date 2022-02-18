// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface ICamelit {
    struct CamelBandit {
        bool isCamel;
        uint8 fur;
        uint8 head;
        uint8 ears;
        uint8 eyes;
        uint8 nose;
        uint8 mouth;
        uint8 neck;
        uint8 body;
        uint8 legs;
        uint8 feet;
    }
    function getPaidTokens() external view returns (uint256);
    function getTokenTraits(uint256 tokenId) external view returns (CamelBandit memory);
}