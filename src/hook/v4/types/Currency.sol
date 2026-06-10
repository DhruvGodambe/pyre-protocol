// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type Currency is address;

library CurrencyLibrary {
    function unwrap(Currency currency) internal pure returns (address) {
        return Currency.unwrap(currency);
    }

    function wrap(address currency) internal pure returns (Currency) {
        return Currency.wrap(currency);
    }
}
