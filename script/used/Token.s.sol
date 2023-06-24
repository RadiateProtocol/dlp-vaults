// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import "src/launch_contracts/PresaleContractFlattened.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RADToken as Token} from "src/modules/TOKEN/RADToken.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";
import {Initialization} from "src/policies/Initialization.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";

contract TokenScript is Script {
    function setUp() public {}

    address[] private arr = [
        0xCFFE08BDf20918007f8Ab268C32f8756494fC8D8,
        0xAd0fc281Ac377794FA417e76D68788a56E3040f0,
        0x3B5f951A87BecF94ef52C84a91684409D28060Aa,
        0x8aEe0E08c61b5810fc9bd274fF69ba2db4492ECE,
        0x98aE9456a99f309956e4182deCE0e4798943B9f6,
        0x6ED88188Da646B6fE64022895dE4045C35EbA48e,
        0x6b49a6B4777C561Bd71F4d5E6cF90fBcFA4116D6,
        0xc1737e5Cb508630f14224d8b77BEFDB348E63a2B,
        0xa2917120C698fb5F2A03e3fD3524bdA85a3eaEF6,
        0x4911505CBb6cC71F71b59eF1EC0ee99f6C57a8A0,
        0x9A451eFa23AAF9F419D8a3EA6ABEe550613fb3dc,
        0x4d744DaAce4AD148eA8B7833d21Be7e2942d9A29,
        0x83F66B8d41DDAB1a5D346181c4346a58e6D83A0C,
        0x3Bf7Ca3737335868d949f80EA017e577A8f8f316,
        0x6bEA1644C14C9082cf42667Eaad4cfA89158EbF0,
        0xcb954F2a0973abc92f9F8eD58938821B219CfE80,
        0x5bAaC7ccda079839C9524b90dF81720834FC039f,
        0x37D34B424dC624a41fE412ab1460d1e0eBEfb8aF,
        0x87013CfD02A863D5ED3Cad31223A81b59dBfDbCD,
        0x1Cc00Cc60f0b031Bb8d460358E27ab2857a07C0D,
        0x4c496ea116A09651778e480B2e7E5aBA78514521,
        0xB2515a7221b2654F9Faae0E4eD1d0E49Aa7B85DD,
        0x2b133847465Ce196015044Afbe675aFdda482e1B,
        0x076a6Faed850c0C2b270E7271A526cB26755F14D,
        0x7637f43CFcc6ae683BB7dCAaD90F0b61b76C573A,
        0x214E59A2e789f5D5881699401145ac72539aF6aB,
        0x0922Bc5098a85C5C406Fb3c2371aF990f9d8dc65,
        0xBF6ce33bce54b40DD6Ba8aAD3a85f6c566fC9D40,
        0xC8Fc69a0A0508C4C8753e36262E23F876E3552Db,
        0x911DA057b7F735bc54E9fFbe1143DdA363dBA6fB,
        0x133e9241Aac55967884d7A141f60Da4da2Fb7B50,
        0xA8992310f620dc8f23F9Cf4faD90A2F2380D8d6a,
        0xE8EE975d5e3B357C1D9719F99c6d3b9614B0442d,
        0x0cECB92B7A674f6E371F7339e3BFdC11418d1259,
        0xa9256a6Ff144B59A55f32C3547aB0d3fe217bAD4,
        0xd0947C8f6e6318696bB2155f30968037fa08BD04,
        0x6b90f246E0057f9C289449EDBE8181E46e239e5B,
        0x1228a857FD7Ee845f4999f33540F6b9D0988e80d,
        0xd1fA3f9BA62cb251e785D2c7Eddd5D0A022BAaE1,
        0x3476C2e44880E020aaaEB80dCd85f7f67D20acC6,
        0x8b5d3e6FD56488c7Bc4F31b93Fa2f2E219fDfb38,
        0xA914604c82BfbEbDd261CC08E72B35AC29259D8B,
        0x7038e012B0683d8Fdb38f127ebb98A01BB30dA27,
        0xD963BE28A687E21FF44c7B3eb822CcE75CE95B88,
        0xf733F39134dEbb3EC637D7Cdd9463a5687AB893C,
        0xe4682c269248F3d9efE7C8EC1A9C73eBdc185b2E,
        0xE5ea58E6531E63C7BB58353F08A492acC8B5Eeb6,
        0xB3639Bcf727216c353B78C2415878b7e52286d44,
        0xC8ba5a463895B09f8362977Be63C48022cAAeAC7,
        0xbD76C6487DaBef207470AFdB6f332c0432482F45,
        0x2412Bd7681B71010a1CD90057DeE4158EC86F08C,
        0x3753E2eDE1fb49cC203f9C3e598B18665fB55D2A,
        0xB4fb31E7B1471A8e52dD1e962A281a732EaD59c1,
        0x6B2ea72Ba8A7346cEdd2Dd5dC1476eA8df0B57D7,
        0x47671c4d89aBB81efF18cc69839C634aF408e8af,
        0x049808d5EAA90a2665b9703d2246DDed34F1EB73,
        0x300F818133Cb321b1099cBD845044390F37e2E22,
        0x6b5b5f2de5FB8Ac403C2632a21B55efC4DCc1Ed3,
        0x8f7fF55bA9880A740a30e75f99e8991cbC382D7b,
        0x16623D088c54A11Afa30faF98f778FBD7f7Fb61F,
        0xaB888291F4127352B655fd476F64AC2ebfb8fe76,
        0x7c6CC4fc9f054F851aa9aE3577087f00e017db5A,
        0x629862337fDDf4d18C543DBaa9B3B7b441900fb5,
        0x3bb20140Af8858a94C9693244e517Ff304299085,
        0xe6f4cCAc6bbc030f4b4735fb9Dbd68526096Ce3D,
        0xe3F186478E9DcD416E3568E56e4153645144093A,
        0x232E03CC440ad5158Bd38636607f0E0Ad62A01c2,
        0x05a2e50C5E4d724897b67b708db432A38c985f83,
        0x2be1a753b1c0562c4cf35A24F6f62619961CEB53,
        0x0cA6CAdb6a8cA4199788b9a060C3285Fe7B897Fd,
        0xC44fD102415FF62769A4e37C70deA27033a5291F,
        0x473d3a2005499301Dc353AFa9D0C9c5980b5188c,
        0x7C43a9C3b85619be2F7C0a4D676eCd373f63b73C,
        0x48Cd090C9E8a9954B0955c8b87754031d90c4955,
        0x61E60af04805D7dDFB0CFDe0A96A3b1C15F3748F,
        0x8F0568899653dC5853954cc02B29C37862982148,
        0xde28e623B919b4A5280Ed97759d3B8e741Ea8fF3,
        0xeAE1e7BDaAADC6D4E0892B0dEFBA3f0111354248,
        0x2A1BBcdff7A047d82fc8829FAA0D13a8D2cf1dBE,
        0x9a54971B7a4c17e93fcFFb4cB11e792065e15d44,
        0x3f2228945C85663b54677dB97dA44DBDE71744ae,
        0x1EeB5ECBb50e4cd52dE4F81D7c07d3fd6CE2e9Fc,
        0xB05Cf01231cF2fF99499682E64D3780d57c80FdD,
        0xb6F6db1F7eBA57094Ebc3891904bB5b34778dB67,
        0xb50A3877f40ba0A019D45cEC9F3d9f01dD4eeD0e,
        0xBCEF7d7a39ed4975b3261c8b226220187b785662,
        0xB3B38F171f12C1543164ac8fc40503827d3B9edc,
        0x3Bf86d166cb46BBf145E94B124dc686493a265aF,
        0x56679F8669f6CDFf2B341F9aaA4055356DaDC8e7,
        0x750685dB51856e2C9B5E839Ab27Fb268b365115b,
        0x3188810bf80C80551b9e15a3D49854190b381aE9,
        0x3f2B9232Ce37d489f846d4464648F14036c6ca12,
        0xa52453C88c29550430F8a0378f1AdE46413ab9d7,
        0xf8FeA0bA658aCAEf401566C9CC6f84fFaB6fCD70,
        0xB41429cf0bD01e587d09369A088e547150c2fE38,
        0x6aF9bd5D67468d8b273B68B57C43956e8397C620,
        0x03b25D7C738C4ba0C319b86C208c2f718eA04D22,
        0x99655CA16C742b46A4a05AFAf0f7798C336Fd279,
        0x3172aee5e0B47bB23e87db93327F58E06e6A73B6,
        0x6c7D2e50B4A588ACB5E88C8f6b76a6218fcE5aF2,
        0xFdfC13a4AceF96e28D4f54bc17857DBD9824a819,
        0x2DCF532DD77845710DC95596cf560ef8B7964104,
        0xFab977091c09cB67A478c824C427b1351Fb204B7,
        0x0452c0a0743C37Af4737e000b1E664f2017f8337,
        0xc5cC3cB22A976C1715D8CC83B6A8E1dBB995A6f5,
        0x10b38E6a0E47cFC69cFB153885b8565Ae2333B74,
        0x48218a6452F65E0b8529d20cb5149b695D48E0C5,
        0x2fA7AB2e6a5c5fd9Af6F9C4a025F04529Ce301cD
    ];

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address multisig = vm.envAddress("RAD_MULTISIG");
        vm.startBroadcast(deployerPrivateKey);
        Kernel kernel = new Kernel();
        Token token = new Token(kernel);
        console2.log("Kernel address: ", address(kernel));

        Treasury treasury = new Treasury(kernel);
        OlympusRoles roles = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(roles));
        console2.log("Roles address: ", address(roles));

        kernel.executeAction(Actions.InstallModule, address(treasury));
        console2.log("Treasury address: ", address(roles));
        kernel.executeAction(Actions.InstallModule, address(token));
        console2.log("Token address: ", address(roles));
        // Activate Policies
        RolesAdmin rolesAdmin = new RolesAdmin(kernel);
        console2.log("Roles Admin address: ", address(roles));
        Initialization initialization = new Initialization(kernel);
        console2.log("Initialization address: ", address(roles));

        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(initialization));
        // Testnet
        // MockERC20 usdc = new MockERC20("usdc", "usdc", 6);
        // deploy Private presale
        RADPresale presale = new RADPresale(
            multisig,
            IERC20(address(token)),
            IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8), // USDC.e on arbi
            7 days
        );
        initialization.setMaxSupply();
        initialization.mint(address(presale), 13333 * 1e18);

        console2.log("Presale address: ", address(presale));

        // Deploy public presale later
        initialization.mint(multisig, 45000 * 1e18); // Team tokens + public presale tokens + airdrop tokens

        initialization.mint(address(treasury), 96000 * 1e18); // DAO treasury tokens

        // Set up roles
        rolesAdmin.grantRole("admin", multisig);
        // whitelist

        kernel.executeAction(Actions.DeactivatePolicy, address(initialization));
        kernel.executeAction(Actions.ChangeExecutor, multisig);
    }
}
