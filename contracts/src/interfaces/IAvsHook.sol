// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IAvsHook {
    function beforeOperatorOptIn(address operator) external;
    function afterOperatorOptIn(address operator) external;
    function beforeOperatorOptOut(address operator) external;
    function afterOperatorOptOut(address operator) external;
}
