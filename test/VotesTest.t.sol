// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusVotes} from "src/modules/VOTES/OlympusVotes.sol";
import {RADToken} from "src/modules/TOKEN/RADToken.sol";

// import "test/lib/ModuleTestFixtureGenerator.sol";

contract VOTESTest is Test {
    // using ModuleTestFixtureGenerator for OlympusVotes;

    uint256 internal MAX_SUPPLY = 10_000_000 * 1e18;

    Kernel internal kernel;

    RADToken internal VOTES;
    MockERC20 internal gOHM;

    address internal user1;
    address internal user2;
    address internal auxUser;

    function setUp() public {
        address[] memory users = new UserFactory().create(1);
        auxUser = users[0];

        // kernel
        kernel = new Kernel();

        // modules
        gOHM = new MockERC20("gOHM", "gOHM", 18);
        VOTES = new RADToken(kernel);

        // generate godmode address
        // user1 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        // user2 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);

        // set up kernel
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        // kernel.executeAction(Actions.ActivatePolicy, user1);
        // kernel.executeAction(Actions.ActivatePolicy, user2);
    }

    function test_default() public {
        assertTrue(true);
    }
}
