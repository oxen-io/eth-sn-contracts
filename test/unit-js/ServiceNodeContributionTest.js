const { expect } = require("chai");
const { ethers } = require("hardhat");

// NOTE: Constants
const STAKING_TEST_AMNT = 15000000000000
const TEST_AMNT         = 50000000000000

const SN_CONTRIB_Status_WaitForOperatorContrib = 0n;
const SN_CONTRIB_Status_OpenForPublicContrib   = 1n;
const SN_CONTRIB_Status_WaitForFinalized       = 2n;
const SN_CONTRIB_Status_Finalized              = 3n;

const BLS_NODES =
[
  {
    blsPubkey: {
      X: BigInt("0x28852e6bd8fc98305370c1636e35d3b1fe30cb5d79e5392b1238f18a1f60a1ed"),
      Y: BigInt("0x1d0a9ed200fc6762ce53b42d6c9173a11c233a8e41d634ec7014c00ebb5ed4b0"),
    },
    blsSig: {
      sigs0: BigInt("0x27ceb4fb24b0cb43c55af0ce2f6463e6d14ec1c7f9edbad7c00fbb31a38e3d53"),
      sigs1: BigInt("0x2386070cdd9a315241a8d351e2185addc042ad36aca524ad93a7862ac452b9a1"),
      sigs2: BigInt("0x2170a69f683f44baabf1c590e6c5863a0d30b84d50144cb2f8cc8cb105fad7e9"),
      sigs3: BigInt("0x0d9e3b16e83584504b5a597e98cfa76f9d7487878b6a03677beed56fe7a1ba39"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x3621a81c1ef05d48fc9be9dd590ab0869a70fa751e40d8fbebdb0d90e285dbd8"),
      serviceNodeSignature1: BigInt("0x9812e9d91f4e468c56f77fdbb6735b50c2c3590055efb38f26796a4630d4da42"),
      serviceNodeSignature2: BigInt("0x40779f125038351141f70f5e8d24cc1b70abcd466a28847551cc1496c13ae209"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x137e85cd37748f14247358e0e44612210aa5fa27a8fbf28ad340c55767f15d2c"),
      Y: BigInt("0x18edb0ca60f8acb2632f940b18ac6ca4600f10f2b266c9d6c5e20124ede3bb8b"),
    },
    blsSig: {
      sigs0: BigInt("0x1d041dfbf3d6c94c4d171f53faae08fdf1124d9a4286e5d54dcc243e88a96a4f"),
      sigs1: BigInt("0x161c04dbf785039cdf5fea0f78a5b481f4daa7049b39a5fdec0a6e735ff09775"),
      sigs2: BigInt("0x26337d0059f0df7311a968162a7c2951aaa3bfc22213f88167ca06777d8f6469"),
      sigs3: BigInt("0x13149ba06fd741964f0068e4691b20417d221d9742ded83ab1db5d2ecb5129d5"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x60a9ab78cf2f4fd0389ca6044c340583089d7aaf85cfa3f273145d9188698c84"),
      serviceNodeSignature1: BigInt("0xd345006a1d3c05e78acf5009518654ccee0e91a3c283f3318ad8038ef39efda0"),
      serviceNodeSignature2: BigInt("0x5bd67009d57f0e225374d85877497916705cc6d486785c377cec6e48ffb3c608"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x00e263487b1cb7c4fc9bb541852ff4f7b92e387d23b53282cf6b48e39ed43232"),
      Y: BigInt("0x1f44ea36abe36bbde3663e8fc297cd102a2b27ae3903618be54a7ae08036224d"),
    },
    blsSig: {
      sigs0: BigInt("0x150e6d24b43b4795789ba54ce0702d26fb47f5700df0578b5f856b9d0e0ba6ea"),
      sigs1: BigInt("0x27913007fc1733b9d92cb7d39793675a8ee383dae6b781cc87b1cc452446e142"),
      sigs2: BigInt("0x2dc9163573b5d957ca2a7ed157966663f12072c5a38bffeb118d82a3a120d407"),
      sigs3: BigInt("0x2ce537e12f0dac9ab0981250a8765f29a97efec899e3403f8b9aa1eaa5050873"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xb7438a21a3d7751c28d62c7a3d64732346c34e11c2d0eca0c9ee70fb8fa2239f"),
      serviceNodeSignature1: BigInt("0xaae240781bcd1d917a8b8cc7aa2e81c936064187bba7b7569f83de1ec74c0cee"),
      serviceNodeSignature2: BigInt("0x0dfc0a89ea3c09c12d886d77d765c1ed95fffba80c5f42bc24a279ae0188a708"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2a92a211da6c48067d5879210432eaec238a5c40e2126a26e200ac6aeb49aeaa"),
      Y: BigInt("0x1c31cc309fbc5df9fbb2572bca05e1ce6144beacfb4e7cebec7492a66811f500"),
    },
    blsSig: {
      sigs0: BigInt("0x2a85406c7ab2a247bfba8076663a3248667a83d152e5827ad865873527a24001"),
      sigs1: BigInt("0x27af0953ff6d57eff077a1347fb8130e91b76a183d74dbeed0679b89f1ac5a4d"),
      sigs2: BigInt("0x03e584d993baa4e2e3e8a6c64ab2867e571e85c9f9beda9af5eed2a4b667c196"),
      sigs3: BigInt("0x01b1b902f8992342a47916fd1840bf621b8c1ef04c0eb50cb3fd6069b969df3c"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x0b6e8e90e2086156e6b01ce4059f9ef97a6f456e06536011239f7af24102d2e8"),
      serviceNodeSignature1: BigInt("0xfd56b10fac88b5d67be19960908729e8f1c29516e01d6c317a7cb60427e2ea56"),
      serviceNodeSignature2: BigInt("0xacaaef5b5efb082609d1b257cfd2803f511cf9685e9ca3542b8ea57afb529e03"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x123d8f7d06354fccf99067720a666f00613c84c32665fa59c4ed3aa400f0d0c0"),
      Y: BigInt("0x27ce8f724005cabe324ea34f07cca97fe8f99f8176e1a77d96cc2e2c2cd02329"),
    },
    blsSig: {
      sigs0: BigInt("0x21f223b0b9fb777895b841208efc2638eb3c7e2f785104120cd6a79489962932"),
      sigs1: BigInt("0x09adfd83eb9debdf3b933b87a65ad767e4c5ed5e704d53e53b18c9ccde53e9de"),
      sigs2: BigInt("0x00d7bbafcc8bdeb75fb9d90bdbbcf30fc11c4850bf1019a673eb3e02477a4f93"),
      sigs3: BigInt("0x262ad5c9aa371b68074eb96a3f8416bb1bac851cb07fb5113edd3aa34336c3d5"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x1ed64b0cf49699d05aa64aee86381d0bb2a22dbab1f21a39a78c994fb3c56c70"),
      serviceNodeSignature1: BigInt("0x67a6c395b66617dc947aa9d12d0bbfbaf4f24f2d0128efc760382d6bcfc19726"),
      serviceNodeSignature2: BigInt("0x84a5edc4fa0281aff3518996611e6580e8447d2bdb893ea678b410eaa845010a"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x209aab3cdbca882beb090142d9d1a95c34487d6b81f154da9d41155134f0bfd4"),
      Y: BigInt("0x103e3a371121df4379af9ae06b779dbbb353deee056ea0605717c022a10ce6fd"),
    },
    blsSig: {
      sigs0: BigInt("0x0836b63a7f048c3a86ca4984878ef9df3ac1aeb357b8adf488ef7ab7cf5e6571"),
      sigs1: BigInt("0x04262a4f27b2f96b78d7b6b46f154d599dcf9dd2accd52d411024aa4113fecef"),
      sigs2: BigInt("0x06e1c11ee880e44becf56c1df474b30c1d6bc1033b5c1750436848326f4f1bb4"),
      sigs3: BigInt("0x0bf7cab6145dc8b5de68acc73dbc670f96fdaf124cb7e9c26c62deee9564c76c"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xc85e5eb5a684268d364a4199c0d7e5944f2b85c5b6e3c7ef401fe68d98a53dcf"),
      serviceNodeSignature1: BigInt("0x7216cbd0a47fd9cc72736e7843cde6c140f66dc33df159780f6e996b4dfa02e3"),
      serviceNodeSignature2: BigInt("0x06283ff1ef5be11b3cb3b1d8ade9f4581b909c633a4b7224c82bc4b8ed640d09"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x1443f4c6bd301155450788983ba2f49f87e9ce5207bc65acc4996d2a49163119"),
      Y: BigInt("0x04f585818363d19ea1f386cf939e06bafb3d4a55eaeea6cb141edcd794a007c6"),
    },
    blsSig: {
      sigs0: BigInt("0x13affae36d9c8bc7b49397b53c6ca396702b313d33ceb5d4844ca4628aa1bbb5"),
      sigs1: BigInt("0x0b2ea0eb381fe46e23c7fcb1edba31391d8c480203614bb2064a932f7ac95b53"),
      sigs2: BigInt("0x0c9fb0b7c23c7b49b2cc3d782bad8f4459c19f8a6b868217c97766b8c1054a6e"),
      sigs3: BigInt("0x082323b29285b4cfecffc0b9fbba476802a6bf93c1dbd18a417a9846b903350a"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xbff0e4a20e54177de1b0bcc4032c4c7d3f6229ea95b167e5ffaab2d1560d8b1f"),
      serviceNodeSignature1: BigInt("0x843c4fa8306def3997e63998e001fed36af4d16c50d6a1aa2a1dc6d297078769"),
      serviceNodeSignature2: BigInt("0x330f05143115063759cd9df4b93d7cd3212263531f72c71e93e613d2ddb83905"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x19611c59b104fe8c31fd25e9f023cfe23b9b1ec54ca8a477e4fc98216e2ce306"),
      Y: BigInt("0x1a0f70876d561611904d07d5e8ba588c291b5fe726fe0236e272ade46e2259a0"),
    },
    blsSig: {
      sigs0: BigInt("0x2d4f788849a10eb1996455e682e4070f4a0674874c46c933741f8b0a69a0134c"),
      sigs1: BigInt("0x0838167d7b9aae775b573e80823bab1f83a6362f252f8d235bea49c142da3ce5"),
      sigs2: BigInt("0x209508c3e4e84001fa47ace418f70be3defa6b3048b3af29985b7c4b15124ef9"),
      sigs3: BigInt("0x15c2a4fd5502b25b75ea7e4660aa9bf0e19110a860b22c4a0569614f1edc77be"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xd2520a52e30c924f0c86ae2a9a949523a705b17d1d69142655091f5218bf5c4b"),
      serviceNodeSignature1: BigInt("0xfbf97716cbcf89a80e9db3cb4c15571477ec1e5dd32f20e68095307752b87ad5"),
      serviceNodeSignature2: BigInt("0x1a5e380008904337e275945c2b9746cfd81276eddbc022d4326953d4c1b09e0d"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x182846f960228dd3f1de63bb5a51aec7955617ae658989b4576a65540aa296ae"),
      Y: BigInt("0x23e347d9865bfd14f0b7a8ae82ce64e4015659c2b6502126c3ed3eb97403fd56"),
    },
    blsSig: {
      sigs0: BigInt("0x00ae871641adc977a12f9afa6f13b093fe7791c8014489132770fba2a716fc1a"),
      sigs1: BigInt("0x1711bdd94828a390aa673afbce35c2dd28870b1cb3cd9ccadaef12b57d16a60c"),
      sigs2: BigInt("0x1252a9ab02bfaf2d79e9016dccbefcbeb109f40da0efa83b7fdd367dfc07c307"),
      sigs3: BigInt("0x122faffcd95d248365583af7a6b98d0803426448536115d7571fe33290026182"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x39612b434b910098770bd91c41a3670436913a30d2c79c3b68eb87a073ce1d71"),
      serviceNodeSignature1: BigInt("0x3bb1a0caae7867c2b2eda29f64513807039e0ee8bb0168e3a05c04b3cd1641c8"),
      serviceNodeSignature2: BigInt("0x910cbeeaf4f58fade5acb5529a50aafdfbc62d8a3513ea8983ff0f2a44b84400"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x25bd989e07a718c58435a7962be9a7ace2ec4f824c8e5cfd3a0184cfcf34affa"),
      Y: BigInt("0x0f1e8b1dce81d6d313ef40a0ad19dde17ccb97f26692b9104b743ed1dd78beaf"),
    },
    blsSig: {
      sigs0: BigInt("0x09cd7df368896131d6ca17616f52144b54a69ab20aa992ab30fc0bfebc939b76"),
      sigs1: BigInt("0x0ff31376e6aae30b22f30a4e8ffd598a2b72faa237ffd8fc9c34b097a2fc3006"),
      sigs2: BigInt("0x07f697daf0909cb95779e0cfb26401aa28dc2c7523e73817337b6a4311e2f6f7"),
      sigs3: BigInt("0x143aa3107ef29c08756c7553d0f1d2063b11f23f31d5a9cf151f438c5b72a92d"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xa70ee247f94f961e3028b77d755702a641ebb16a30ca186679f5def5556c4a50"),
      serviceNodeSignature1: BigInt("0x2dbca64535ed30145ecf6bee568219f510b2626ef01f357482898a518c4e38bb"),
      serviceNodeSignature2: BigInt("0xc2dbdd978a0de07674978aff929d3e1a2ee75eb701e6fa13e106ce06c0128805"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x096977a21e8605d8b2245a76e880bc570265aac68b8a8b7c38a06c9def8066ca"),
      Y: BigInt("0x0e23c0b402bcecab1e8128e564a2bd7ba5fe5329e87ab20475a1507b77e23e5b"),
    },
    blsSig: {
      sigs0: BigInt("0x21835f6859a4276e848f468abcbb324618028899d092aeae1cf311be6387ce80"),
      sigs1: BigInt("0x2714c0c26bb4c29aa36a485b937b46d93d168f4e753b15cabf64defd9458adce"),
      sigs2: BigInt("0x199f2397b24fdabbd1c3df94be43a97ee6a2fb9592c51e7f8d18796d83310980"),
      sigs3: BigInt("0x15038360f67ae90ab24f12ee3e884a8dbe4ec1af8baeca303863d74009ac5360"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x3c44371e2fa72a05e815a4c07cab2667ad86b56afcf95fbb3ebdc63bd3460f66"),
      serviceNodeSignature1: BigInt("0x00542d59e976f83e20ebe0d3298cfeaabf177ba2aed3197e3a4d2ecc33b0958d"),
      serviceNodeSignature2: BigInt("0xa4bcb7e26dc18a0901b75fb2e8eddebf3bc2fb6d34b56523501598d8856c7d05"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2cfa3ef1da4983fb6a50ba1002ade018b7014ce60f101f58bc4eec13421bad33"),
      Y: BigInt("0x05f3cfb69c9056f683e67480a22c571ecdc11e5a349b8c243e70bcf8d94dca35"),
    },
    blsSig: {
      sigs0: BigInt("0x29185144c266ee6e9c1432e2ed759acfab10000bd3cfe316498270760a1d8e3b"),
      sigs1: BigInt("0x11c1e2426d8f15f90061db5cb8e01d35bc540aca537ff945d4ed0f655e7f4ee4"),
      sigs2: BigInt("0x2322ec37b28683bf503bb8930c64b779af91a9f2cb5e942aa5c8df0f80bce076"),
      sigs3: BigInt("0x0b8ff123ced67439ecfddf23a57c4903be348c5f13a000c6628f0494906d59af"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xeb3d965c59788cc6be3a08166022b67138491192717872ccd0c9516962b72960"),
      serviceNodeSignature1: BigInt("0x69c05d859950faf5d2975e4daf5fb7a37461ea2658bd878feea36111c56eb773"),
      serviceNodeSignature2: BigInt("0x095f12d52d7eddd1f58758815e7ef95e609d084a2cc8e74e671322208e113f02"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x17be111378daa6db6f25800febc347c963dae28aca90ee9d9c078dfb2fed2ed9"),
      Y: BigInt("0x2ed72ff3375b97b8e846d03d973a53c7975c4566db597d0555af5125735e7c85"),
    },
    blsSig: {
      sigs0: BigInt("0x251f70697411082c7469123db5e076e337fced03a8638874f763f99e3319779b"),
      sigs1: BigInt("0x1efb75b479d48b146fb2f724ac392da31721db79415f1063f4aba9616441e3aa"),
      sigs2: BigInt("0x0845c99a822631dea2dbde2bb139fa39fe94aa18656789f784cd79d30068f2e3"),
      sigs3: BigInt("0x14e4896435ceee8c9044ceacbe17c3d7eaeb1bb706961da0dd73567ef2b08e50"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x0b6f21f6f03180b48106c1be74ebb0122e3c68535c05a3414f6ef00633057552"),
      serviceNodeSignature1: BigInt("0xea675b4b68db3c7029f93be6a4baca1d2a48563c1eab17246800d4604b0c71b5"),
      serviceNodeSignature2: BigInt("0x8661e318beb0e7944d78468d480846c30722151bd090e0a9bf68c7664b334405"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x0bd297e8689e20252118dd0a39d471a6b338e2739ecc8938df7a375f750cf04b"),
      Y: BigInt("0x275a87e4ce241984b88654b7f0b960dfc608d64ff03458c30f8abb955bc223a7"),
    },
    blsSig: {
      sigs0: BigInt("0x01848b1850931c8ed52ac418fc1c935631e9cd44e9eebffd1424ff2523faf296"),
      sigs1: BigInt("0x0c03f373374f1cfae8506550152afa8b79a32649435d343df816bb0a455957e7"),
      sigs2: BigInt("0x1b9d2ae10b9f7fa66f9642c6c6e3f6b337b77f8160049020a4852c82a1ed22bb"),
      sigs3: BigInt("0x2dca478a947edd13eaf7da881b48c50c493fe1f4c31db403e515e2eb1dc459d9"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xfa92911f6f1e4fdf56d22fc3bcc18c9cd5351726f5425bb25b3d428baaa5511a"),
      serviceNodeSignature1: BigInt("0xe9d44703ab7a78b165a9d81965f21444ee2b9c6968ce9aaec0c090fab282fe9c"),
      serviceNodeSignature2: BigInt("0x2dbe2bfbd5c39123635043535b46af1ecf96a104dd8a5114d423311c424c7b00"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x29985dd0f92f2ae9632d708dd91da7145c6e40d71cd76f00c3c95a910dc09bfd"),
      Y: BigInt("0x2d30a2aa7ed2d0e55e815df44d782660541305eda954d58b94bc7453955a661b"),
    },
    blsSig: {
      sigs0: BigInt("0x1cadfb1c96363a34c267e1821c9bb27f6dd4c707885b8684635142a1c48033f6"),
      sigs1: BigInt("0x03847010ae081cb8d2f778e0d394f722567b2c7abf09bbfb3eead033f1ff2ad1"),
      sigs2: BigInt("0x0ddf77ab293d95725b68472839258b6ea1280fddd1f94c50e369c1ea87188c8d"),
      sigs3: BigInt("0x252b31553f5e4c8e5e898d513cc662f23d43ec1284da2fdc39f8b574d5a44272"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x494d67ae14397c555802d5a5800725ff10dcf82241d115430e174900660bc221"),
      serviceNodeSignature1: BigInt("0x0a7578601af1f970dd7bb3d33a075b3f6eb163d2dcd6c844c8cf33d489189caf"),
      serviceNodeSignature2: BigInt("0xc4affde89d1c6cc49ab431afc116bb219758443c5d66711462fd5cf9d66f5205"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x0c0f214777d0e217f9f8dc5736d3aef36f1922664d2bea9ec5fb4875a2e141f2"),
      Y: BigInt("0x08218fd363afce310728890190f6e5859790e58cf77278083345393f7a3febc9"),
    },
    blsSig: {
      sigs0: BigInt("0x29542eb8deb031c56da78646d2f38b7233e581deb578efa11ab018f6271f9a8d"),
      sigs1: BigInt("0x045e0ab2b0e22854c056c61bd47a2f15d32d2845e3b889fa5dc3a3bb866de7bd"),
      sigs2: BigInt("0x29055a1513585f6c586281e4fe76c87f954830f5ff1433374da1360fb16f9ad5"),
      sigs3: BigInt("0x28a7adbf1aaaf5f12d0461927d2ff0dd736bced5d8f2a34607d2f6c06c4164c5"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x9c441483bff8484e7847c7a90aa647f862a921ba47df571f4d921bf015f5a07f"),
      serviceNodeSignature1: BigInt("0xdf767ae0293edd8cc24e97ccb46293110d8f63cb81ff71ead4265eec3b879789"),
      serviceNodeSignature2: BigInt("0x08906fcc617bfc28baf12cfac81ca9aa91aaf0c68a8dd4be653b26e00f28db07"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2de0b341b75e0a43bce35ffcc1b3fff810bf3e24201d51ff2252602e9cc7ac63"),
      Y: BigInt("0x11a75bf5ccccf90e46d70e048a440cac64042017defa929df744cc652dd0b66b"),
    },
    blsSig: {
      sigs0: BigInt("0x1abdd319b1e0df8b1d303fbcd3cf6687c766561a3de397c1232d7cf9af111c77"),
      sigs1: BigInt("0x2ca59c2f6b41004254c49b9f43ef014b35805e8e71d8ca450af1ad3530bf5b4e"),
      sigs2: BigInt("0x2fcbd1ec0011acbec3aa77f74e4ca27b2550dd6eb40d8888298f36ad9e634a08"),
      sigs3: BigInt("0x044a260c9624a6efce96accf426a8b9775b67f6ab8be7a27d23000066cd25941"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x20a03cb0a6ecd45c1f6cb2166f39f1d50a942cb9bb965dd24541ef197750e4fc"),
      serviceNodeSignature1: BigInt("0xcf75333dfabec9b3b5d0986d86bad1129e849fffcaf2444aad177490245afb8b"),
      serviceNodeSignature2: BigInt("0x5dce10e5b07972a1b773c007ff949b497f0afebf67e35d5a096132c96967c008"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x0ec4e939d75ef9a0f9e552fdf665aa8d4d05062f6e361b5048fa6636449cad76"),
      Y: BigInt("0x01822e42323c5d9059b85332bc3add7a82270f19624752fe5171f90c46200576"),
    },
    blsSig: {
      sigs0: BigInt("0x20992eabfb62329980b76652fa2daabd9b3f17a9cb92a3e19a9b627e4ef2af9c"),
      sigs1: BigInt("0x2e2ed20c7f25234448492a69288bdd51da5f83caf3c887b9f0a4e87442364f02"),
      sigs2: BigInt("0x26c27b9529f6f5bf5b093bdf90497a516d76d5b275d90a4c974e3592ab3ea04e"),
      sigs3: BigInt("0x20a7be778ae97212f3ff94f192dc6d350b201bdc0eb598c5f1fdcefee60ab7f3"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x7080cf28d96821f1217a096d4452928afb81bcd33a64b538d13e1acc019c1025"),
      serviceNodeSignature1: BigInt("0xb8e21fe14e62d419f21ee9d1fa15fe2bcde6e1a76bf15332b618102d1a12d976"),
      serviceNodeSignature2: BigInt("0x558f5a879d4efcae20137045bfb05fb4b9ee1993a67df9671dc1ae22a202a402"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2dea7299533dd41653481d23fe5537d76379943670f254716eaa4cf240ba7e42"),
      Y: BigInt("0x17790118a4c560a89e463fd95f6e992bfc19e974307549c0f55d901ea83850df"),
    },
    blsSig: {
      sigs0: BigInt("0x09f7fd8d541af63ae6d6206d93511016e90f25f1c8d8de152a2247165009dc6b"),
      sigs1: BigInt("0x1f582bc07769b4251daf9c13d1f6adad900eb1e94a8062a084b0233655948198"),
      sigs2: BigInt("0x2fc8ca7c49e4b734eaca9d62a2b36eaba1a9b30b060e16115dbd4453043df28c"),
      sigs3: BigInt("0x0588ff460a500b702fdde71508372a13f0670c7ce7ff4cd6cc68814454c5fc48"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x56986a952f6c61637c000c7684b80b8d6d872d7d7e19b97943c7f93aae0d62d0"),
      serviceNodeSignature1: BigInt("0xc6c0b75042f7cac96067900560b302f94239c0ae74e1177a70cee5f31148d785"),
      serviceNodeSignature2: BigInt("0xd6819d5dd5f8bbaf5e71782fe2b4cea053a337c05b0e700110eb9342062da90f"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2f007aa95227793251728351f741315ccf1ba112fe8c8620d3f3ac8981b9bd25"),
      Y: BigInt("0x10aa18cbe84a5c8a448b934fb6fafa405f9ddb7e80514f06493912bb63a8546e"),
    },
    blsSig: {
      sigs0: BigInt("0x1b65b67a591f806cc5264d41420716408c0eab93649ce385dbd181b7c719d951"),
      sigs1: BigInt("0x20ece1a5b40c5a82bab58250bb6549882e65dc7efae0986297edc199c4004015"),
      sigs2: BigInt("0x1a0dd5595664682069226cf4f3d60506dd9f87aa4fcad0d24308fada6212fd4a"),
      sigs3: BigInt("0x2559531489c797a12d113e7c16ceae04c2b8a7750a0a554ce0b8e2624d5e9933"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xdfad945674cd891399ebbb4f1526928a5ac82c7f1f8e1aa32982552b0752ad9f"),
      serviceNodeSignature1: BigInt("0xb805ca0fba3628079109390debb77896ae382354ef5bd61cf89c06e2b2987301"),
      serviceNodeSignature2: BigInt("0x2706d9d8dd08ec4b191bf8d9ff1d4668bb18245fc9b80303c8fc6d1a194bd60a"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x22015431b30510a6af2f2948db96afc17d23c03f9142eef86f3ae2a729a43895"),
      Y: BigInt("0x25cc5a304298dae1646a15e8d816ea29479e4b6d3aa26cf4bedd2eac132d9892"),
    },
    blsSig: {
      sigs0: BigInt("0x12dde295782cfc54f746162b4d2a474f6246e7e17028cd979130fc2da92643dc"),
      sigs1: BigInt("0x281b394cf22a78bbd32e15b5ccd8f26e6c81ccc34633b3e39e9c8272eb496e4b"),
      sigs2: BigInt("0x1615576abaa5b4cec2f70a5daa9db48c8f895ac05191cad169328f78a225f6eb"),
      sigs3: BigInt("0x2e697cbefc0db2777773fc6e1413f08594ca517ddc27f4b034d73b4d58fd9b1d"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xcdd99eafca8e77077fe400250890c6326dabae778bb4c5a44fb7848224b72994"),
      serviceNodeSignature1: BigInt("0x4d820c3b376e9d410c76800713cbfdb93d8f3bfbb854eb39ac0c2ebc9b5b584e"),
      serviceNodeSignature2: BigInt("0x51916cfae230b215756cf437003c6a4f2a799a3dafa4bb4a0a0816263d2a690c"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x13954f6ef8348b7410bea6f04aeef3546561bd150220500349adccd0b7586157"),
      Y: BigInt("0x07a345ef26808211bd71aac7ac83f9d5bb3497962b7a2e9fe035b2262683fb8f"),
    },
    blsSig: {
      sigs0: BigInt("0x172b0c6ee1348ab8235eb313d44eb18a7c130fe85cb1ff160aa12d5d0ff3e978"),
      sigs1: BigInt("0x1072ae312b52c70471a34377a1163bb6c7aa20dd75a76e71cfe95b9c3e3c36fb"),
      sigs2: BigInt("0x0ad3b09f38deebe77fde589f7e6c5bbeb9143419bcd9e74d8b04b0b2294056c5"),
      sigs3: BigInt("0x061070288c38fd07dafc838a89f1b5debb7adb19ede47e172cf40a957355dcc7"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x551ca95c57a6d9cd5a1e43c5259ddb10f36b898bd9475dcf4a75c67ac572b422"),
      serviceNodeSignature1: BigInt("0xd7a22b402e3ee3e51e75de9fcc6349e7484ff6df6c674e0f36d8309716b4dc74"),
      serviceNodeSignature2: BigInt("0xc3a517c26dbb9a6acab55eb3550624570b4cf5ec5c8da369a148e2b537d5a00c"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x01cc948a02678a7a535e1e46f468479534e89f99f557b578ef4c099863ead083"),
      Y: BigInt("0x2e830be9c04cc13350c29e7f19b2fa2c4734c6eee6fd2807662fbeaf50d6519e"),
    },
    blsSig: {
      sigs0: BigInt("0x00576f875c9d2191e17a5c16ea233a9c489d5a1aa5b0a1f1c3e43e10c0bba616"),
      sigs1: BigInt("0x0924374df060feb9e1b7aae300daaf8421013f4a314c7757be54a824bf5cca19"),
      sigs2: BigInt("0x009b9151b2eaef44dc2bf48e6a3bb5d34cbe1773c87cffb8d369888aa45b165d"),
      sigs3: BigInt("0x0212c32d1627e168bc12b8ef065ca90fdb003b539842a445e49d51071e6629a7"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xfd763741128552bb0c125660e3929580ac4e42a27f58b9e895390d898f2df6db"),
      serviceNodeSignature1: BigInt("0x8359fedaefdbe22136cb305e348e12bba731d60cc2515321fac05c7ac70078e2"),
      serviceNodeSignature2: BigInt("0xab6326ec2abcd72234d3b28457ee8d5d4051db523632ac000439b03b8832f80d"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x24c2834dd3a1b3bfcaa840472ff8874a3c41a3aa47c225ba8ed747c86624ea36"),
      Y: BigInt("0x13e42ca9526d8f00af5d630eb467224aafd3fefa0084ce8cf52345820bfc5dd8"),
    },
    blsSig: {
      sigs0: BigInt("0x1711626f697d8ee5c19c75b2fb707187dca3c6ad8f697932479bc0eddf17100d"),
      sigs1: BigInt("0x27b4b6cb0e6fe789def479326dbba4e9aaf618aab17e4336e944754a91d15fad"),
      sigs2: BigInt("0x2b16153ccfb915f041da55d04f19026b87e19aa8728c629e5645308d851ca646"),
      sigs3: BigInt("0x00e4a706955e54cb4265fd448cc704fc4386dbe1ba5051c7242e438c1c6e7ab7"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x1bd45174e045509672be9d79b2b08daee3377fa9735e2de6a25eee06abf86e0a"),
      serviceNodeSignature1: BigInt("0x50633ea8b285b0145080e3032ce244e5840162bc71e4f60c75733af796733771"),
      serviceNodeSignature2: BigInt("0xfe78bd2feee1f9cfa7b7246b07aee89cd2b2107fb3aaa9f644f49a523ef70a09"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x02ac1a70efc57022242c7ce38727986fd5d0c5df64fb49cb93ae81bcd86a58d9"),
      Y: BigInt("0x2f4696606a2d3c41ed9aa13c00c59bd4e0da6c42a936b32485daab0b4fff98ac"),
    },
    blsSig: {
      sigs0: BigInt("0x2d3597bae2f0be39cf29c2bb658cd9d2121b38ef4f9cb2fe492b763165bde6b5"),
      sigs1: BigInt("0x167ad53ee93fb08e24ac27833ca13ef1a2da8f331743fe1561ae7259904dc92d"),
      sigs2: BigInt("0x04261a5acdbe73f072b6cc7bacd7693a8cd769e89064bce7b30b6e625c165bd8"),
      sigs3: BigInt("0x09bbac1155ab76de6ff3dabe7ac8e743cd55340aaf402dd533df0e7ed38924fa"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xd87676d42a9ab23f6c8df2fafd98e5f89d4f70fc774a6c7c56c0ca2252d33167"),
      serviceNodeSignature1: BigInt("0xd0e31d609268922cb9d51b91e4a93a0d67ff049924ae0d81b13de05121a92adc"),
      serviceNodeSignature2: BigInt("0x67d5bf3641caf4334d1f8141c89cd6e2b880d706911a56bc0516611c953c8404"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x1da7dd5ab1d032519024588918150bffbac49eb0a510adde1d5877a6dd7a5b63"),
      Y: BigInt("0x13a8e9bab3fb3c59cce9cbfc3558582e141342de0f7795a548f1cb5ae7b05afc"),
    },
    blsSig: {
      sigs0: BigInt("0x2e4c2cb551cc8c4ba10cd2ad9f3adddbeca4106b01597c78f2f75ad064ffdb26"),
      sigs1: BigInt("0x2b3b501c3c840a38301454d76443d8cf400d435873d57db1aa72135398763a0d"),
      sigs2: BigInt("0x0031270fd8c21d7735d81c4ac7af655a4a768c1704cc192ca633be04862b87a9"),
      sigs3: BigInt("0x2c32a7380eca05dcd79366b896e4cad746881e2624c2378d87558af890cc29a9"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xa9da24bb4a9dab8be99d58b9e9fcbf66822460f8409c1d6217e2afce19555c40"),
      serviceNodeSignature1: BigInt("0xc2c1a1894cdf830b29cd6ece75e3312d5bfe4afb4e2da85f7f9304f27706ea08"),
      serviceNodeSignature2: BigInt("0xef40f78fd972a31a9ccf36c1180b202231d6f5e1237f6d64fcf0bedcc37eca04"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2507f00a71765b0ed9e040ef480ce60dfca5588fb4a581272fe217df731b5fc3"),
      Y: BigInt("0x0349ffa821acde181bcdbfa337b04d632bb58f27cd060e1aa78f47911eb6e898"),
    },
    blsSig: {
      sigs0: BigInt("0x2707ad200e769e43b1b2a9eb0f59500e2678e227759ce25103c6597b86a57ba2"),
      sigs1: BigInt("0x2b4ff8fab4c3501444190d521e68d6abe3486b333a182af0646c67160152aaae"),
      sigs2: BigInt("0x2d47e58fe5fa1ff84df6c08e5432f54aebb073b137e8988a36cf8d06ea604027"),
      sigs3: BigInt("0x1fe328021768e25c223d7f1d9b5559467b041d0aa25c83c68eff01c6e4474850"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x400e9d6aea71a0ddc9437f3a6d88143e97ed6e34e555f461002102408a6dafc3"),
      serviceNodeSignature1: BigInt("0x9c3358c9985af83d4bb0392d43aaed38d4557e25ee72c1f4028bd155c626b70c"),
      serviceNodeSignature2: BigInt("0xa350067f7308337ebc47dad262e5582cfb5873b992461332e677a7e4208f4c04"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x05b5b9227ef533dd49040c6ce4e1a93f3df6ac2ae6d9ba5e9959a8fe4d10b92e"),
      Y: BigInt("0x173b966038e62362e649f28cfa09b010f788827a2b1ad63b7f84f957f20fc6ba"),
    },
    blsSig: {
      sigs0: BigInt("0x0c2d9716d6a702bc25638a80c98205eb1e7143e9673cda6d3666ce05aab71adf"),
      sigs1: BigInt("0x0b723f41dc2441ad722e863b6f53fe2e0ad26b47b44610890899390ad5b10e36"),
      sigs2: BigInt("0x25f823c84e04fc45a4e1349bf9eb309ea6ff8a535a8e62ceca099583f2786444"),
      sigs3: BigInt("0x2f12318ee77935535195fc5abd559f7740acb9ab39523f28bb4d548deb5ac7de"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x5829fb01d7539926b2463e8a35ac798369ebd642e2130f4a7b449a2a88f1e6fb"),
      serviceNodeSignature1: BigInt("0x5acca3a7ae9127063c09e10e011d4e12ff947facc2083ae099e9b5dc5882ac5a"),
      serviceNodeSignature2: BigInt("0x82c42374728bc3cf4abbad0364c00863e3ebb8d73ad4e72f6101ffcb83c59f0b"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2066a7489a70a2b395335401cd7375d45a5bc8c5085651daf951439ae14c0314"),
      Y: BigInt("0x1041263f4baf69e67dffb4d5f52d804a09e19b039b110c66ed4408015ced52c0"),
    },
    blsSig: {
      sigs0: BigInt("0x0efff018b76a03c512b499b006fc9143cb37963157e96fe165b84fea98b81fd3"),
      sigs1: BigInt("0x10468aad1d5ab38c4ffcd52def5c6d9dca410c58b6650fa7b0c8e5e25745c090"),
      sigs2: BigInt("0x17ab8c8828bb7025a8a69796212dfeff60015cca496ed741202bed83c164cfcd"),
      sigs3: BigInt("0x11f3b6faebae906ee3721f4656b1ebb9a19900e6719ef8f27c6f32e484abc34f"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x12bb5ae2f236b8827b8a0c044f68264dddbefa4d68f3f209a56a11bd51e94fb3"),
      serviceNodeSignature1: BigInt("0x7d89f8eb73c620340c261d3efd0d592eb4b12f519307d16d1fb14b451bcc270b"),
      serviceNodeSignature2: BigInt("0x3321c4b3de662ea12c2d5cac8562622aad19dce0ec92eb955d78746841847e08"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x160be0b06b932f991ffc127b8ef80baf5ad3859830b3f334d90fed1ef3873ed4"),
      Y: BigInt("0x2284ff08fadb388cc8d802751aa53580b18fd8c0e246121b9ed221b247317475"),
    },
    blsSig: {
      sigs0: BigInt("0x2a5e3c7035ba94dae7a1e273cc12d40bfd601483e932ae4843db28d330c1e086"),
      sigs1: BigInt("0x1917f98b6c14932b79e09d91943ed2f0a9edefe70658cbaad4ac921734e71823"),
      sigs2: BigInt("0x211f8063bdf8e78f45aa4a176b6f2e14eb0b3a6a9502eb5f03b1c4fa166e5aa7"),
      sigs3: BigInt("0x175d64fa71c27ca0cc9b6bfb70748480aab2c1378fefc90ab18288c2a57b8f9f"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x862a46abe75dd90539d81f0b8714dfb37c2293defc1b98b1d7c1c512366dd066"),
      serviceNodeSignature1: BigInt("0x4cb21b66397de331738756bb371231dbd252e9048ba814e27b53fc0175ce1279"),
      serviceNodeSignature2: BigInt("0xececceaff8c0c2f40d9e732c3d582c045df9d1864f68a3d491648b49a22f1a05"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x060e873484be102cf10592e488e624e6904f73b1fa95d47ddb5b8de811b470d5"),
      Y: BigInt("0x246bf8c34e566fbb12cc3be9e3e722af2b008a5ac3c8c16a57912d03bc27efc6"),
    },
    blsSig: {
      sigs0: BigInt("0x1968d96e0d4e133c5f5b9cabaac7db6ce4a48b6e06962b41ab639a6f30abf1a6"),
      sigs1: BigInt("0x048cf851c84f442a7635806ecb1d3b0aa6b217d72b86727cb51cbf9d7352a293"),
      sigs2: BigInt("0x0a98669e74b4dba9a8a3ea226c806ae3e5ea6d3997246cdde518ee08cbe9f350"),
      sigs3: BigInt("0x0fe8c2eb75795e4d80084f619c188fec1b600bceef6358a87a0d58fb509babef"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0xfe2bb85c64266574c8d7eea8e721a4b92f33a550d10d349d0b7fe30ceaf629af"),
      serviceNodeSignature1: BigInt("0xae17a8f67d1bcac1a2215be42fd6c78ce636a579c7daf137b429a868a522f948"),
      serviceNodeSignature2: BigInt("0x46c81065ab384f3cc80f614d57fe78609407a5040c1e0b99cb879b1251fe6502"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  },
  {
    blsPubkey: {
      X: BigInt("0x2bdf0ee5e85c9106b337d6799a6d82b73c4c3665343d39c2dfb396cd1168e499"),
      Y: BigInt("0x07725be5ea5b9b2179c319c6e9d545f2cd56c1916740e5900ce378bb94ac0e62"),
    },
    blsSig: {
      sigs0: BigInt("0x1245945c4de7616899972e0c2aa5eae10fc4c9b2e3c6dc1ddc81c2d4ca5b8c39"),
      sigs1: BigInt("0x17c750940e98af0a9c56c0e9fd744603e08f0f840a3f628c8f779a3c35224270"),
      sigs2: BigInt("0x261bb4fffc2dabda57f62cb4f3531e91a0ea51cd99fa8446f6b5a6a2dfface0b"),
      sigs3: BigInt("0x26efccb8c68ab06a16a36ef1e8b6a4964b7a466a6685dd6efde2d98703858574"),
    },
    snParams: {
      serviceNodePubkey: BigInt("0x02601845e40c4a81d867b37d39c5c67fb6aabd9cf009060b0fa7f74e76c3db2d"),
      serviceNodeSignature1: BigInt("0x191e554b134265a6da7d467462f8839cc09d139a888d9d7e7fe28ad8c892d9ff"),
      serviceNodeSignature2: BigInt("0x2eb8b0d1a67749625623c4c6592d5bf447f744ae4c3f9e754db0e67a32a93908"),
      fee: 0
    },
    contributors: [
      {
        addr: BigInt("0x66d801a70615979d82c304b7db374d11c232db66"),
        stakedAmount: STAKING_TEST_AMNT,
      }
    ],
    reserved: [
    ]
  }
];

// Withdraw a contributor from the service node contribution contract
// `snContribution`. This function expects to succeed (e.g. the contributor must
// have successfully contributed to the contract prior).
async function withdrawContributor(sentToken, snContribution, contributor) {
    // NOTE: Collect contract initial state
    const contributorTokenBalanceBefore = await sentToken.balanceOf(contributor);
    const contributorAmount             = await snContribution.contributions(contributor);
    const totalContribution             = await snContribution.totalContribution();
    const contributorAddressesLength    = await snContribution.contributorAddressesLength();

    let contributorArrayBefore = [];
    for (let index = 0; index < contributorAddressesLength; index++) {
        const address = await snContribution.contributorAddresses(index);
        contributorArrayBefore.push(address);
    }

    // NOTE: Withdraw contribution
    await snContribution.connect(contributor).withdrawContribution();

    // NOTE: Test stake is withdrawn to contributor
    expect(await sentToken.balanceOf(contributor)).to.equal(contributorTokenBalanceBefore + contributorAmount);

    // NOTE: Test repeated withdraw is allowed but balance should not change because we've already withdrawn
    await expect(snContribution.connect(contributor).withdrawContribution()).to.not.be.reverted;
    expect(await sentToken.balanceOf(contributor)).to.equal(contributorTokenBalanceBefore + contributorAmount);

    // NOTE: Test contract state
    expect(await snContribution.totalContribution()).to.equal(totalContribution - contributorAmount);
    expect(await snContribution.contributorAddressesLength()).to.equal(contributorAddressesLength - BigInt(1));

    // NOTE: Calculate the expected contributor array, emulate the swap-n-pop
    // idiom as used in Solidity.
    let contributorArrayExpected = contributorArrayBefore;
    for (let index = 0; index < contributorArrayExpected.length; index++) {
        if (BigInt(contributorArrayExpected[index]) === BigInt(await contributor.getAddress())) {
            contributorArrayExpected[index] = contributorArrayExpected[contributorArrayExpected.length - 1];
            contributorArrayExpected.pop();
            break;
        }
    }

    // NOTE: Query the contributor addresses in the contract
    const contributorArrayLengthAfter = await snContribution.contributorAddressesLength();
    let contributorArray = [];
    for (let index = 0; index < contributorArrayLengthAfter; index++) {
        const address = await snContribution.contributorAddresses(index);
        contributorArray.push(address);
    }

    // NOTE: Compare the contributor array against what we expect
    expect(contributorArrayExpected).to.deep.equal(contributorArray);
}

describe("ServiceNodeContribution Contract Tests", function () {
    // NOTE: Contract factories for deploying onto the blockchain
    let sentTokenContractFactory;
    let snRewardsContractFactory;
    let snContributionContractFactory;

    // NOTE: Contract instances
    let sentToken;             // ERC20 token contract
    let snRewards;             // Rewards contract that pays out SN's
    let snContributionFactory; // Smart contract that deploys `ServiceNodeContribution` contracts

    // NOTE: Load the contracts factories in
    before(async function () {
        sentTokenContractFactory      = await ethers.getContractFactory("MockERC20");
        snRewardsContractFactory      = await ethers.getContractFactory("MockServiceNodeRewards");
        snContributionContractFactory = await ethers.getContractFactory("ServiceNodeContributionFactory");
    });

    // NOTE: Initialise the contracts for each test
    beforeEach(async function () {
        // NOTE: Deploy contract instances
        sentToken             = await sentTokenContractFactory.deploy("SENT Token", "SENT", 9);
        snRewards             = await snRewardsContractFactory.deploy(sentToken, STAKING_TEST_AMNT);
        snContributionFactory = await snContributionContractFactory.deploy(snRewards);
    });

    it("Verify staking rewards contract is set", async function () {
        expect(await snContributionFactory.stakingRewardsContract()).to
                                                                    .equal(await snRewards.getAddress());
    });

    it("Allows deployment of multi-sn contribution contract and emits log correctly", async function () {
        const [owner, operator] = await ethers.getSigners();
        const node = BLS_NODES[0];
        await expect(snContributionFactory.connect(operator)
                                          .deployContributionContract(node.blsPubkey,
                                                                      node.blsSig,
                                                                      node.snParams,
                                                                      node.reserved)).to.emit(snContributionFactory, 'NewServiceNodeContributionContract');
    });

    describe("Deploy a contribution contract", function () {
        let snContribution;        // Multi-sn contribution contract created by `snContributionFactory`
        let snOperator;            // The owner of the multi-sn contribution contract, `snContribution`
        let snContributionAddress; // The address of the `snContribution` contract

        beforeEach(async function () {
            [snOperator] = await ethers.getSigners();

            // NOTE: Deploy the contract
            const node = BLS_NODES[0];
            const tx = await snContributionFactory.connect(snOperator)
                                                  .deployContributionContract(node.blsPubkey,
                                                                              node.blsSig,
                                                                              node.snParams,
                                                                              node.reserved);

            // NOTE: Get TX logs to determine contract address
            const receipt                  = await tx.wait();
            const event                    = receipt.logs[0];
            expect(event.eventName).to.equal("NewServiceNodeContributionContract");

            // NOTE: Get deployed contract address
            snContributionAddress = event.args[0]; // This should be the address of the newly deployed contract
            snContribution        = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);
        });

         describe("Minimum contribution tests", function () {
             it('Correct minimum contribution when there is one last contributor', async function () {
                 const contributionRemaining = 100;
                 const numberContributors = 9;
                 const maxContributors = 10;

                 const minimumContribution = await snContribution.calcMinimumContribution(
                     contributionRemaining,
                     numberContributors,
                     maxContributors
                 );

                 expect(minimumContribution).to.equal(100);
             });

             it('Correct minimum contribution when there are no contributors', async function () {
                 const contributionRemaining = 15000;
                 const numberContributors = 0;
                 const maxContributors = 4;

                 const minimumContribution = await snContribution.calcMinimumContribution(
                     contributionRemaining,
                     numberContributors,
                     maxContributors
                 );

                 expect(minimumContribution).to.equal(3750);
             });

             it('Equally split minimum contribution across 4 contributors', async function () {
                 let contributionRemaining = BigInt(15000)
                 let numberContributors    = 0;
                 const maxContributors     = 4;
                 for (let numberContributors = 0; numberContributors < maxContributors; numberContributors++) {
                     const minimumContribution  = await snContribution.calcMinimumContribution(contributionRemaining, numberContributors, maxContributors);
                     contributionRemaining     -= minimumContribution;
                     expect(minimumContribution).to.equal(3750);
                 }
                 expect(contributionRemaining).to.equal(0)
             });

             it('Correct minimum contribution after a single contributor', async function () {
                 const contributionRemaining = 15000 - 3750;
                 const numberContributors    = 1;
                 const maxContributors       = 10;

                 const minimumContribution = await snContribution.calcMinimumContribution(
                     contributionRemaining,
                     numberContributors,
                     maxContributors
                 );

                 expect(minimumContribution).to.equal(1250);
             });

             it('Calc min contribution API returns correct operator minimum contribution', async function () {
                 const maxContributors             = await snContribution.maxContributors();
                 const stakingRequirement          = await snContribution.stakingRequirement();
                 const minimumOperatorContribution = await snContribution.minimumOperatorContribution(stakingRequirement);
                 for (let i = 1; i < maxContributors; i++) {
                     const amount = await snContribution.calcMinimumContribution(
                         stakingRequirement,
                         /*numContributors*/ 0,
                         i
                     );
                     expect(amount).to.equal(minimumOperatorContribution);
                 }
             });

             it('Minimum contribution reverts with bad parameters numbers', async function () {
                 const stakingRequirement = await snContribution.stakingRequirement();

                 // NOTE: Test no contributors
                 await expect(snContribution.calcMinimumContribution(stakingRequirement, /*numberContributors*/ 0, /*maxContributors*/ 0)).to
                                                                                                                                          .be
                                                                                                                                          .reverted

                 // NOTE: Test number of contributers greater than max contributors
                 await expect(snContribution.calcMinimumContribution(stakingRequirement, /*numberContributors*/ 3, /*maxContributors*/ 2)).to
                                                                                                                                          .be
                                                                                                                                          .reverted

                 // NOTE: Test 0 staking requirement
                 await expect(snContribution.calcMinimumContribution(0, /*numberContributors*/ 1, /*maxContributors*/ 2)).to
                                                                                                                         .be
                                                                                                                         .reverted

                 // NOTE: Test number of contributors equal to max contributors (e.g. division by 0)
                 await expect(snContribution.calcMinimumContribution(stakingRequirement, /*numberContributors*/ 3, /*maxContributors*/ 3)).to
                                                                                                                                          .be
                                                                                                                                          .reverted
             });
         });

         it("Does not allow contributions if operator hasn't contributed", async function () {
             const [owner, contributor] = await ethers.getSigners();
             const minContribution      = await snContribution.minimumContribution();
             await sentToken.transfer(contributor, TEST_AMNT);
             await sentToken.connect(contributor).approve(snContributionAddress, minContribution);
             await expect(snContribution.connect(contributor).contributeFunds(minContribution))
                 .to.be.revertedWith("The operator must initially contribute to open the contract for contribution");
         });

         it("Reset contribution contract before operator contributes", async function () {
             await expect(await snContribution.connect(snOperator).reset())
             expect(await snContribution.contributorAddressesLength()).to.equal(0);
             expect(await snContribution.totalContribution()).to.equal(0);
             expect(await snContribution.operatorContribution()).to.equal(0);
         });

         it("Random wallet can not reset contract (test onlyOperator() modifier)", async function () {
             const [owner] = await ethers.getSigners();

             randomWallet = ethers.Wallet.createRandom();
             randomWallet = randomWallet.connect(ethers.provider);
             owner.sendTransaction({to: randomWallet.address, value: BigInt(1 * 10 ** 18)});

             await expect(snContribution.connect(randomWallet)
                                                 .reset()).to
                                                          .be
                                                          .reverted;
         });

         it("Prevents operator contributing less than min amount", async function () {
             const minContribution = await snContribution.minimumContribution();
             await sentToken.transfer(snOperator, TEST_AMNT);
             await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
             await expect(snContribution.connect(snOperator).contributeFunds(minContribution - BigInt(1)))
                 .to.be.revertedWith("Public contribution is below the minimum allowed");
         });

         it("Allows operator to contribute and records correct balance", async function () {
             const minContribution = await snContribution.minimumContribution();
             await sentToken.transfer(snOperator, TEST_AMNT);
             await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
             await expect(snContribution.connect(snOperator).contributeFunds(minContribution))
                   .to.emit(snContribution, "NewContribution")
                   .withArgs(await snOperator.getAddress(), minContribution);

             await expect(await snContribution.operatorContribution())
                 .to.equal(minContribution);
             await expect(await snContribution.totalContribution())
                 .to.equal(minContribution);
             await expect(await snContribution.contributorAddressesLength())
                 .to.equal(1);
         });

         describe("After operator has set up funds", function () {
             beforeEach(async function () {
                 const [owner]         = await ethers.getSigners();
                 const minContribution = await snContribution.minimumContribution();

                 await sentToken.transfer(snOperator, TEST_AMNT);
                 await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
                 await expect(snContribution.connect(snOperator)
                                            .contributeFunds(minContribution)).to
                                                                             .emit(snContribution, "NewContribution")
                                                                             .withArgs(await snOperator.getAddress(), minContribution);
             });

             it("Should be able to contribute funds as a contributor", async function () {
                 const [owner, contributor] = await ethers.getSigners();
                 const minContribution = await snContribution.minimumContribution();
                 let previousContribution = await snContribution.totalContribution();
                 await sentToken.transfer(contributor, TEST_AMNT);
                 await sentToken.connect(contributor).approve(snContribution, minContribution);
                 await expect(snContribution.connect(contributor).contributeFunds(minContribution))
                       .to.emit(snContribution, "NewContribution")
                       .withArgs(await contributor.getAddress(), minContribution);
                 await expect(await snContribution.operatorContribution())
                     .to.equal(previousContribution);
                 await expect(await snContribution.totalContribution())
                     .to.equal(previousContribution + minContribution);
                 await expect(await snContribution.contributorAddressesLength())
                     .to.equal(2);
             });

             it("Should allow operator top-ups", async function() {
                 const minContribution = await snContribution.minimumContribution();
                 const topup = BigInt(9_000000000);
                 await expect(topup).to.be.below(minContribution)
                 const currTotal = await snContribution.totalContribution();
                 await sentToken.connect(snOperator).approve(snContribution, topup);
                 await expect(snContribution.connect(snOperator).contributeFunds(topup))
                       .to.emit(snContribution, "NewContribution")
                       .withArgs(await snOperator.getAddress(), topup);
                 await expect(await snContribution.operatorContribution())
                     .to.equal(currTotal + topup);
                 await expect(await snContribution.totalContribution())
                     .to.equal(currTotal + topup);
                 await expect(await snContribution.contributorAddressesLength())
                     .to.equal(1);
                 await expect(await snContribution.minimumContribution()).to.equal(
                     minContribution - BigInt(1_000000000));

                 await expect(await snContribution.getContributions()).to.deep.equal(
                         [[snOperator.address], [BigInt(STAKING_TEST_AMNT / 4 + 9_000000000)]])
             });

             describe("Should be able to have multiple contributors w/min contribution", async function () {
                 beforeEach(async function () {
                     // NOTE: Get operator contribution
                     const [owner, contributor1, contributor2] = await ethers.getSigners();
                     const previousContribution                = await snContribution.totalContribution();

                     // NOTE: Contributor 1 w/ minContribution()
                     const minContribution1                   = await snContribution.minimumContribution();
                     await sentToken.transfer(contributor1, minContribution1);
                     await sentToken.connect(contributor1).approve(snContribution, minContribution1);
                     await expect(snContribution.connect(contributor1)
                                                         .contributeFunds(minContribution1)).to
                                                                                            .emit(snContribution, "NewContribution")
                                                                                            .withArgs(await contributor1.getAddress(), minContribution1);

                     // NOTE: Contributor 2 w/ minContribution()
                     const minContribution2 = await snContribution.minimumContribution();
                     await sentToken.transfer(contributor2, minContribution2);
                     await sentToken.connect(contributor2)
                                    .approve(snContribution,
                                            minContribution2);
                     await expect(snContribution.connect(contributor2)
                                                         .contributeFunds(minContribution2)).to
                                                                                            .emit(snContribution, "NewContribution")
                                                                                            .withArgs(await contributor2.getAddress(), minContribution2);

                     // NOTE: Check contribution values
                     expect(await snContribution.operatorContribution()).to
                                                                        .equal(previousContribution);
                     expect(await snContribution.totalContribution()).to
                                                                     .equal(previousContribution + minContribution1 + minContribution2);
                     expect(await snContribution.contributorAddressesLength()).to
                                                                              .equal(3);
                 });

                 it("Should allow contributor top-ups", async function() {
                     const [owner, contributor1, contributor2] = await ethers.getSigners();
                     const minContribution = await snContribution.minimumContribution();
                     const initialOperatorContrib = await snContribution.operatorContribution();
                     const initialContribution = await snContribution.totalContribution();

                     const topup1 = BigInt(1_000000000);
                     await sentToken.transfer(contributor1, topup1);
                     await expect(topup1).to.be.below(minContribution)
                     await sentToken.connect(contributor1).approve(snContribution, topup1);
                     await expect(snContribution.connect(contributor1).contributeFunds(topup1))
                           .to.emit(snContribution, "NewContribution")
                           .withArgs(await contributor1.getAddress(), topup1);

                     const minContribution2 = await snContribution.minimumContribution();
                     const topup2 = BigInt(13_000000000);
                     await sentToken.transfer(contributor2, topup2);
                     await expect(topup2).to.be.below(minContribution2)
                     await sentToken.connect(contributor2).approve(snContribution, topup2);
                     await expect(snContribution.connect(contributor2).contributeFunds(topup2))
                           .to.emit(snContribution, "NewContribution")
                           .withArgs(await contributor2.getAddress(), topup2);

                     await expect(await snContribution.operatorContribution())
                         .to.equal(initialOperatorContrib);
                     await expect(await snContribution.totalContribution())
                         .to.equal(initialContribution + topup1 + topup2);
                     await expect(await snContribution.contributorAddressesLength())
                         .to.equal(3);
                     await expect(await snContribution.minimumContribution()).to.equal(
                         minContribution - BigInt(2_000000000));

                     await expect(await snContribution.getContributions()).to.deep.equal(
                         [
                             [owner.address, contributor1.address, contributor2.address],
                             [BigInt(STAKING_TEST_AMNT / 4), BigInt(STAKING_TEST_AMNT / 12 + 1_000000000), BigInt(STAKING_TEST_AMNT / 12 + 13_000000000)]
                         ])
                 });

                  describe("Withdraw contributor 1", async function () {
                      beforeEach(async function () {
                          const [owner, contributor1, contributor2] = await ethers.getSigners();

                          // NOTE: Advance time
                          await network.provider.send("evm_increaseTime", [60 * 60 * 24]);
                          await network.provider.send("evm_mine");

                          await withdrawContributor(sentToken, snContribution, contributor1);
                      });

                      describe("Withdraw contributor 2", async function () {
                          beforeEach(async function () {
                              const [owner, contributor1, contributor2] = await ethers.getSigners();
                              await withdrawContributor(sentToken, snContribution, contributor2);
                          });

                          describe("Contributor 1, 2 rejoin", async function() {
                              beforeEach(async function() {
                                  // NOTE: Get operator contribution
                                  const [owner, contributor1, contributor2] = await ethers.getSigners();
                                  const previousContribution                = await snContribution.totalContribution();

                                  const stakingRequirement = await snContribution.stakingRequirement();
                                  expect(previousContribution).to.equal(await snContribution.minimumOperatorContribution(stakingRequirement));

                                  // NOTE: Contributor 1 w/ minContribution()
                                  const minContribution1                   = await snContribution.minimumContribution();
                                  await sentToken.transfer(contributor1, minContribution1);
                                  await sentToken.connect(contributor1).approve(snContribution, minContribution1);
                                  await expect(snContribution.connect(contributor1)
                                                                      .contributeFunds(minContribution1)).to
                                                                                                         .emit(snContribution, "NewContribution")
                                                                                                         .withArgs(await contributor1.getAddress(), minContribution1);

                                  // NOTE: Contributor 2 w/ minContribution()
                                  const minContribution2 = await snContribution.minimumContribution();
                                  await sentToken.transfer(contributor2, minContribution2);
                                  await sentToken.connect(contributor2)
                                                 .approve(snContribution,
                                                         minContribution2);
                                  await expect(snContribution.connect(contributor2)
                                                                      .contributeFunds(minContribution2)).to
                                                                                                         .emit(snContribution, "NewContribution")
                                                                                                         .withArgs(await contributor2.getAddress(), minContribution2);

                                  // NOTE: Check contribution values
                                  expect(await snContribution.operatorContribution()).to
                                                                                     .equal(previousContribution);
                                  expect(await snContribution.totalContribution()).to
                                                                                  .equal(previousContribution + minContribution1 + minContribution2);
                                  expect(await snContribution.contributorAddressesLength()).to
                                                                                           .equal(3);
                              });

                              it("Reset node and check contributor funds have been returned", async function() {
                                  const [owner, contributor1, contributor2] = await ethers.getSigners();
                                  // Get initial balances
                                  const initialBalance1 = await sentToken.balanceOf(contributor1.address);
                                  const initialBalance2 = await sentToken.balanceOf(contributor2.address);
                                  // Get contribution amounts
                                  const contribution1 = await snContribution.contributions(contributor1.address);
                                  const contribution2 = await snContribution.contributions(contributor2.address);
                                  // Cancel the node
                                  // await snContribution.connect(owner).reset();
                                  // Check final balances
                                  // const finalBalance1 = await sentToken.balanceOf(contributor1.address);
                                  // const finalBalance2 = await sentToken.balanceOf(contributor2.address);
                                  // expect(finalBalance1).to.equal(initialBalance1 + contribution1);
                                  // expect(finalBalance2).to.equal(initialBalance2 + contribution2);
                              });
                          });
                      });
                  });
             });

             it("Max contributors cannot be exceeded", async function () {
                 expect(await snContribution.contributorAddressesLength()).to.equal(1); // SN operator
                 expect(await snContribution.maxContributors()).to.equal(await snRewards.maxContributors());

                 const signers         = [];
                 const maxContributors = Number(await snContribution.maxContributors()) - 1; // Remove SN operator from list

                 for (let i = 0; i < maxContributors + 1 /*Add one more to exceed*/; i++) {
                     // NOTE: Create wallet
                     let wallet = await ethers.Wallet.createRandom();
                     wallet     = wallet.connect(ethers.provider);

                     // NOTE: Fund the wallet
                     await sentToken.transfer(await wallet.getAddress(), TEST_AMNT);
                     await snOperator.sendTransaction({
                         to:    await wallet.getAddress(),
                         value: ethers.parseEther("1.0")
                     });

                     signers.push(wallet);
                 }

                 // NOTE: Contribute
                 const minContribution = await snContribution.minimumContribution();
                 for (let i = 0; i < signers.length; i++) {
                     const signer          = signers[i];
                     await sentToken.connect(signer).approve(snContribution, minContribution);

                     if (i == (signers.length - 1)) {
                         await expect(snContribution.connect(signer)
                                                    .contributeFunds(minContribution)).to
                                                                                      .be
                                                                                      .reverted;
                     } else {
                         await expect(snContribution.connect(signer)
                                                    .contributeFunds(minContribution)).to
                                                                                      .emit(snContribution, "NewContribution")
                                                                                      .withArgs(await signer.getAddress(), minContribution);
                     }
                 }

                 expect(await snContribution.totalContribution()).to.equal(await snContribution.stakingRequirement());
                 expect(await snContribution.contributorAddressesLength()).to.equal(await snContribution.maxContributors());
                 expect(await snContribution.status()).to.equal(SN_CONTRIB_Status_WaitForFinalized);
                 expect(await snContribution.finalize()).to.emit(snContribution, "Finalized");
             });

             it("Should not finalise if not full", async function () {
                 const [owner, contributor] = await ethers.getSigners();
                 const minContribution = await snContribution.minimumContribution();
                 let previousContribution = await snContribution.totalContribution();
                 await sentToken.transfer(contributor, minContribution);
                 await sentToken.connect(contributor).approve(snContribution, minContribution);

                 await expect(await snContribution.connect(contributor).contributeFunds(minContribution))
                     .to.emit(snContribution, "NewContribution")
                     .withArgs(await contributor.getAddress(), minContribution);

                 await expect(snContribution.finalize()).to.be.reverted;

                 await expect(await snContribution.connect(snOperator).status()).to.equal(SN_CONTRIB_Status_OpenForPublicContrib)
                 await expect(await sentToken.balanceOf(snContribution))
                     .to.equal(previousContribution + minContribution);
             });

             it("Should not be able to overcapitalize", async function () {
                 const [owner, contributor, contributor2] = await ethers.getSigners();
                 const stakingRequirement = await snContribution.stakingRequirement();
                 let previousContribution = await snContribution.totalContribution();
                 await sentToken.transfer(contributor, stakingRequirement - previousContribution);
                 await sentToken.connect(contributor).approve(snContribution, stakingRequirement - previousContribution + BigInt(1));
                 await expect(snContribution.connect(contributor).contributeFunds(stakingRequirement - previousContribution + BigInt(1)))
                     .to.be.revertedWith("Contribution exceeds the staking requirement of the contract, rejected");
             });

             describe("Finalise w/ 1 contributor", async function () {
                 beforeEach(async function () {
                     const [owner, contributor1] = await ethers.getSigners();
                     const stakingRequirement = await snContribution.stakingRequirement();
                     let previousContribution = await snContribution.totalContribution();

                     await sentToken.transfer(contributor1, stakingRequirement - previousContribution);
                     await sentToken.connect(contributor1)
                                    .approve(snContribution, stakingRequirement - previousContribution);

                     await expect(await snContribution.connect(contributor1).contributeFunds(stakingRequirement - previousContribution)).to.not.be.reverted;
                     expect(await sentToken.balanceOf(snContribution)).to.equal(stakingRequirement);

                     await snContribution.connect(snOperator).finalize();
                     expect(await sentToken.balanceOf(snRewards)).to.equal(stakingRequirement);
                     expect(await snRewards.totalNodes()).to.equal(1);

                     await expect(await snContribution.connect(snOperator).status()).to.equal(SN_CONTRIB_Status_Finalized);
                     expect(await sentToken.balanceOf(snContribution)).to.equal(0);
                 });

                 it("Check withdraw is no-op via operator and contributor", async function () {
                     const [owner, contributor1, contributor2] = await ethers.getSigners();
                     await expect(snContribution.connect(owner).withdrawContribution()).to.not.emit;
                     await expect(snContribution.connect(contributor1).withdrawContribution()).to.not.emit;
                     await expect(snContribution.connect(contributor2).withdrawContribution()).to.not.emit;
                 });

                 it("Check reset contract is reverted with invalid parameters", async function () {
                     const [owner, contributor1, contributor2] = await ethers.getSigners();
                     const zero                                = BigInt(0);
                     const one                                 = BigInt(1);

                     // NOTE: Test reset w/ contributor1 and contributor2 (of
                     // which contributor2 is not one of the actual
                     // contributors of the contract).
                     await expect(snContribution.connect(contributor1).reset()).to
                                                                               .be
                                                                               .reverted;
                     await expect(snContribution.connect(contributor2).reset()).to
                                                                               .be
                                                                               .reverted;
                 });

                 it("Check reset contract works with min contribution", async function () {
                     const [owner, contributor1, contributor2] = await ethers.getSigners();
                     const stakingRequirement                  = await snContribution.stakingRequirement();
                     const minOperatorContribution             = await snContribution.minimumOperatorContribution(stakingRequirement);

                     // NOTE: Test reset w/ operator
                     const blsSignatureBefore      = await snContribution.blsSignature();
                     const blsPubkeyBefore         = await snContribution.blsPubkey();
                     const serviceNodeParamsBefore = await snContribution.serviceNodeParams();
                     const maxContributorsBefore   = await snContribution.maxContributors();

                     await sentToken.connect(owner).approve(snContributionAddress, minOperatorContribution);
                     await expect(snContribution.connect(owner).reset()).to.not.be.reverted;
                     await expect(snContribution.connect(owner).contributeFunds(minOperatorContribution)).to
                                                                                                         .emit(snContribution, "NewContribution");

                     // NOTE: Verify contract state
                     expect(await snContribution.contributorAddressesLength()).to.equal(1);
                     expect(await snContribution.contributions(owner)).to.equal(minOperatorContribution);
                     expect(await snContribution.contributorAddresses(0)).to.equal(await owner.getAddress());
                     expect(await snContribution.status()).to.equal(SN_CONTRIB_Status_OpenForPublicContrib);
                     expect(await snContribution.blsSignature()).to.deep.equal(blsSignatureBefore);
                     expect(await snContribution.blsPubkey()).to.deep.equal(blsPubkeyBefore);
                     expect(await snContribution.serviceNodeParams()).to.deep.equal(serviceNodeParamsBefore);
                     expect(await snContribution.maxContributors()).to.equal(maxContributorsBefore);
                 });

                 it("Check we can rescue ERC20 tokens sent after finalisation", async function() {
                     const [owner, contributor1, contributor2] = await ethers.getSigners();

                     // NOTE: Check that the contract SENT balance is empty
                     const contractBalance = await sentToken.balanceOf(snContribution);
                     expect(contractBalance).to.equal(BigInt(0));

                     // NOTE: Transfer tokens to the contract after it was finalised
                     await sentToken.transfer(snContribution, TEST_AMNT);

                     // NOTE: Check contributors can't rescue the token
                     await expect(snContribution.connect(contributor1)
                                                .rescueERC20(sentToken)).to.be.reverted;
                     await expect(snContribution.connect(contributor2)
                                                .rescueERC20(sentToken)).to.be.reverted;

                     // NOTE: Check that the operator can rescue the tokens
                     const balanceBefore = await sentToken.balanceOf(owner);
                     expect(await snContribution.connect(owner)
                                                .rescueERC20(sentToken));

                     // NOTE: Verify the balances
                     const balanceAfter         = await sentToken.balanceOf(owner);
                     const contractBalanceAfter = await sentToken.balanceOf(snContribution);
                     expect(balanceBefore + BigInt(TEST_AMNT)).to.equal(balanceAfter);
                     expect(contractBalanceAfter).to.equal(BigInt(0));

                     // NOTE: Tokes are rescued, contract is empty, test that no
                     // one can rescue, not even the operator (because the
                     // balance of the contract is empty).
                     await expect(snContribution.connect(contributor1)
                                                .rescueERC20(sentToken)).to.be.reverted;
                     await expect(snContribution.connect(contributor2)
                                                .rescueERC20(sentToken)).to.be.reverted;
                     await expect(snContribution.connect(owner)
                                                .rescueERC20(sentToken)).to.be.reverted;
                 });
             });

             it("Should allow operator to withdraw (which resets the contract)", async function () {
                 const [owner, contributor] = await ethers.getSigners();
                 await snContribution.connect(owner).withdrawContribution();
                 await expect(await snContribution.status()).to.equal(SN_CONTRIB_Status_WaitForOperatorContrib)
             });

             it("Should revert withdrawal if less than 24 hours have passed", async function () {
                 const [owner, contributor] = await ethers.getSigners();
                 const minContribution = await snContribution.minimumContribution();
                 // Setting up contribution
                 await sentToken.transfer(contributor, TEST_AMNT);
                 await sentToken.connect(contributor).approve(snContribution, minContribution);
                 await snContribution.connect(contributor).contributeFunds(minContribution);

                 // Attempting to withdraw before 24 hours
                 await network.provider.send("evm_increaseTime", [60 * 60 * 23]); // Fast forward time by 23 hours
                 await network.provider.send("evm_mine");

                 // This withdrawal should fail
                 await expect(snContribution.connect(contributor).withdrawContribution())
                     .to.be.revertedWith("Withdrawal unavailable: 24 hours have not passed");
             });

             it("Should allow withdrawal and return funds after 24 hours have passed", async function () {
                 const [owner, contributor] = await ethers.getSigners();
                 const minContribution = await snContribution.minimumContribution();
                 // Setting up contribution
                 await sentToken.transfer(contributor, TEST_AMNT);
                 await sentToken.connect(contributor).approve(snContribution, minContribution);
                 await snContribution.connect(contributor).contributeFunds(minContribution);

                 // Waiting for 24 hours
                 await network.provider.send("evm_increaseTime", [60 * 60 * 24]); // Fast forward time by 24 hours
                 await network.provider.send("evm_mine");

                 // Checking the initial balance before withdrawal
                 const initialBalance = await sentToken.balanceOf(contributor.getAddress());

                 // Performing the withdrawal
                 await expect(snContribution.connect(contributor).withdrawContribution())
                     .to.emit(snContribution, "WithdrawContribution")
                     .withArgs(await contributor.getAddress(), minContribution);

                 // Verify that the funds have returned to the contributor
                 const finalBalance = await sentToken.balanceOf(contributor.getAddress());
                 expect(finalBalance).to.equal(initialBalance + minContribution);
            });
         });
    });

    describe("Reserved Contributions testing minimum amounts", function () {
        let snOperator;
        let snContributionAddress;
        let reservedContributor1;
        let reservedContributor2;
        let reservedContributor3;
        let ownerContribution;

        beforeEach(async function () {
            [snOperator, reservedContributor1, reservedContributor2, reservedContributor3] = await ethers.getSigners();
            const node = BLS_NODES[0];
            let tx = await snContributionFactory.connect(snOperator)
                .deployContributionContract(node.blsPubkey,
                                            node.blsSig,
                                            node.snParams,
                                            []);

            const receipt = await tx.wait();
            const event = receipt.logs[0];
            snContributionAddress = event.args[0];
            snContribution = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);

            ownerContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, ownerContribution);
        });

        it("should succeed with valid reserved contributions: [25% operator, 10%, 10%, 15%, 40%]", async function () {
            const reservedContributors = [
                { addr: snOperator,                           stakedAmount: ownerContribution            },
                { addr: reservedContributor1.address,         stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor2.address,         stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor3.address,         stakedAmount: STAKING_TEST_AMNT * 15 / 100 },
                { addr: ethers.Wallet.createRandom().address, stakedAmount: STAKING_TEST_AMNT * 40 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors)).to.not.be.reverted;
            await expect(snContribution.connect(snOperator).contributeFunds(ownerContribution)).to.not.be.reverted;
        });

        it("should fail with duplicate reserved contributions", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 15 / 100 },
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors)).to.be.revertedWith("Duplicate address in reserved contributors");
        });

        it("should fail with invalid reserved contributions: [25% operator, 10%, 5%]", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 10 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 5 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("should succeed with valid reserved contributions: [25% operator, 70%, 5%]", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 70 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 5 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors)).to.not.be.reverted;
            await expect(snContribution.connect(snOperator).contributeFunds(ownerContribution)).to.not.be.reverted;
        });

        it("should fail with invalid reserved contributions order: [25%, 5%, 70%]", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 5 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 70 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("should fail if operator contribution is explicitly less than 25%", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution - 1n},
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 75 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors))
                .to.be.revertedWith("Contribution is below minimum requirement");
        });

        it("should fail if operator contribution is implicitly less than 25%", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: (STAKING_TEST_AMNT * 75 / 100) + 1}
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors)).to.be.reverted;
        });

        it("should succeed with exactly 25% operator stake", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 75 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors)).to.not.be.reverted;
            await expect(snContribution.connect(snOperator).contributeFunds(ownerContribution)).to.not.be.reverted;
        });

        it("should fail if total contributions exceed 100%", async function () {
            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: STAKING_TEST_AMNT * 50 / 100 },
                { addr: reservedContributor2.address, stakedAmount: STAKING_TEST_AMNT * 30 / 100 }
            ];

            await expect(snContribution.connect(snOperator).updateReservedContributors(reservedContributors))
                .to.be.revertedWith("Sum of reserved contribution slots exceeds the staking requirement");
        });
    });

    describe("Reserved Contributions", function () {
        let snContribution;
        let snOperator;
        let snContributionAddress;
        let reservedContributor1;
        let reservedContributor2;
        let contribution1     = STAKING_TEST_AMNT / 3;
        let contribution2     = STAKING_TEST_AMNT / 4;
        let ownerContribution = STAKING_TEST_AMNT / 4;

        beforeEach(async function () {
            [snOperator, reservedContributor1, reservedContributor2] = await ethers.getSigners();

            const reservedContributors = [
                { addr: snOperator,                   stakedAmount: ownerContribution },
                { addr: reservedContributor1.address, stakedAmount: contribution1 },
                { addr: reservedContributor2.address, stakedAmount: contribution2 }
            ];

            const node = BLS_NODES[0];
            const tx = await snContributionFactory.connect(snOperator)
                .deployContributionContract(node.blsPubkey,
                                            node.blsSig,
                                            node.snParams,
                                            reservedContributors);

            const receipt         = await tx.wait();
            const event           = receipt.logs[0];
            snContributionAddress = event.args[0];
            snContribution        = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);

            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, ownerContribution);
            await snContribution.connect(snOperator).contributeFunds(ownerContribution);
        });

        it("Should correctly set reserved contributions", async function () {
            const reservedContribution1 = await snContribution.reservedContributions(reservedContributor1.address);
            const reservedContribution2 = await snContribution.reservedContributions(reservedContributor2.address);

            expect(reservedContribution1).to.equal(contribution1);
            expect(reservedContribution2).to.equal(contribution2);
        });

        it("Should correctly calculate total reserved contribution", async function () {
            const totalReserved = await snContribution.totalReservedContribution();
            expect(totalReserved).to.equal(contribution1 + contribution2);
        });

        it("Should allow reserved contributor to contribute reserved funds", async function () {
            await sentToken.transfer(reservedContributor1.address, contribution1);
            await sentToken.connect(reservedContributor1).approve(snContribution.getAddress(), contribution1);

            await expect(snContribution.connect(reservedContributor1).contributeFunds(contribution1))
                .to.emit(snContribution, "NewContribution")
                .withArgs(reservedContributor1.address, contribution1);

            const contribution = await snContribution.contributions(reservedContributor1.address);
            expect(contribution).to.equal(contribution1);

            const remainingReserved = await snContribution.reservedContributions(reservedContributor1.address);
            expect(remainingReserved).to.equal(0);
        });

        it("Should prevent reserved contributor to contribute less than their reserved funds", async function () {
            await sentToken.transfer(reservedContributor1.address, contribution1);
            await sentToken.connect(reservedContributor1).approve(snContribution.getAddress(), contribution1);

            await expect(snContribution.connect(reservedContributor1).contributeFunds(contribution1 - 1))
                .to.be.revertedWith("Contribution is below the amount reserved for that contributor");

            const contribution = await snContribution.contributions(reservedContributor1.address);
            expect(contribution).to.equal(0);

            const remainingReserved = await snContribution.reservedContributions(reservedContributor1.address);
            expect(remainingReserved).to.equal(contribution1);
        });

        it("Should allow reserved contributor to contribute more than their reserved funds", async function () {
            await sentToken.transfer(reservedContributor1.address, contribution1 + 1);
            await sentToken.connect(reservedContributor1).approve(snContribution.getAddress(), contribution1 + 1);

            await expect(snContribution.connect(reservedContributor1).contributeFunds(contribution1 + 1))
                .to.emit(snContribution, "NewContribution")
                .withArgs(reservedContributor1.address, contribution1 + 1);

            const contribution = await snContribution.contributions(reservedContributor1.address);
            expect(contribution).to.equal(contribution1 + 1);

            const remainingReserved = await snContribution.reservedContributions(reservedContributor1.address);
            expect(remainingReserved).to.equal(0);
        });

        it("Should update minimum contribution based on reserved amounts", async function () {
            const minContribution = await snContribution.minimumContribution();
            const expectedMin = await snContribution.calcMinimumContribution(
                await snContribution.stakingRequirement() - BigInt(ownerContribution + contribution1 + contribution2),
                3,
                await snContribution.maxContributors()
            );
            expect(minContribution).to.equal(expectedMin);
        });

        it("Should not allow other contributors to fill the node past the sum of the reserved and already contributed", async function () {
            const amountToFillNode = await snContribution.stakingRequirement() - BigInt(ownerContribution);
            const [contributor] = await ethers.getSigners();

            await sentToken.transfer(contributor.address, amountToFillNode);
            await sentToken.connect(contributor).approve(snContribution.getAddress(), amountToFillNode);

            await expect(snContribution.connect(contributor).contributeFunds(amountToFillNode))
                .to.be.revertedWith("Contribution exceeds the staking requirement of the contract, rejected");
        });
    });

    describe("Update registration functions", function () {
        let snContribution;
        let snOperator;
        let oldNode = BLS_NODES[0];
        let newNode = BLS_NODES[1];

        beforeEach(async function () {
            [snOperator] = await ethers.getSigners();

            // Deploy the contract
            const node = BLS_NODES[0];
            const tx = await snContributionFactory.connect(snOperator)
                  .deployContributionContract(oldNode.blsPubkey,
                                              oldNode.blsSig,
                                              oldNode.snParams,
                                              []);

            const receipt = await tx.wait();
            const event = receipt.logs[0];
            const snContributionAddress = event.args[0];
            snContribution = await ethers.getContractAt("ServiceNodeContribution", snContributionAddress);

            // Contribute operator funds
            const minContribution = await snContribution.minimumContribution();
            await sentToken.transfer(snOperator, TEST_AMNT);
            await sentToken.connect(snOperator).approve(snContributionAddress, minContribution);
        });

        it("Should allow operator to update fee before other contributions", async function () {
            await expect(snContribution.connect(snOperator).updateFee(1n))
                .to.not.be.reverted;

            const params = await snContribution.serviceNodeParams();
            expect(params.serviceNodePubkey).to.equal(oldNode.snParams.serviceNodePubkey);
            expect(params.fee).to.equal(1n);
            expect(params.serviceNodeSignature1).to.deep.equal(oldNode.snParams.serviceNodeSignature1);
            expect(params.serviceNodeSignature2).to.deep.equal(oldNode.snParams.serviceNodeSignature2);
        });

        it("Should allow operator to update pubkeys before other contributions", async function () {
            await expect(snContribution.connect(snOperator)
                                       .updatePubkeys(newNode.blsPubkey,
                                                      newNode.blsSig,
                                                      newNode.snParams.serviceNodePubkey,
                                                      newNode.snParams.serviceNodeSignature1,
                                                      newNode.snParams.serviceNodeSignature2)).to.not.be.reverted;

            const blsPubkey = await snContribution.blsPubkey();
            expect(blsPubkey.X).to.equal(newNode.blsPubkey.X);
            expect(blsPubkey.Y).to.equal(newNode.blsPubkey.Y);

            const params = await snContribution.serviceNodeParams();
            expect(params.serviceNodePubkey).to.equal(newNode.snParams.serviceNodePubkey);
            expect(params.serviceNodeSignature1).to.equal(newNode.snParams.serviceNodeSignature1);
            expect(params.serviceNodeSignature2).to.equal(newNode.snParams.serviceNodeSignature2);
        });

        it("Should fail to update fee after operator contributes", async function () {
            // Contribute
            const minContribution = await snContribution.minimumContribution();
            await sentToken.connect(snOperator).approve(snContribution.target, minContribution);
            await snContribution.connect(snOperator).contributeFunds(minContribution);

            await expect(snContribution.connect(snOperator).updateFee(1n))
                .to.be.revertedWith("Contract can not accept new fee, already received operator contribution");
        });

        it("Should fail to update pubkeys after another contributor has joined", async function () {
            // Contribute
            const minContribution = await snContribution.minimumContribution();
            await sentToken.connect(snOperator).approve(snContribution.target, minContribution);
            await snContribution.connect(snOperator).contributeFunds(minContribution);

            await expect(snContribution.connect(snOperator)
                                       .updatePubkeys(newNode.blsPubkey,
                                                      newNode.blsSig,
                                                      newNode.snParams.serviceNodePubkey,
                                                      newNode.snParams.serviceNodeSignature1,
                                                      newNode.snParams.serviceNodeSignature2))
                .to.be.revertedWith("Contract can not accept new public keys, already received operator contribution");
        });

        it("Should fail to update fee after contract is finalized", async function () {
            // Finalize the contract
            const stakingRequirement  = await snContribution.stakingRequirement();
            await sentToken.connect(snOperator).approve(snContribution.target, stakingRequirement);
            await snContribution.connect(snOperator).contributeFunds(stakingRequirement);
            await expect(snContribution.finalize()).to.not.be.reverted;

            // Try to update fee after finalization
            await expect(snContribution.connect(snOperator).updateFee(1n))
                .to.be.revertedWith("Contract can not accept new fee, already received operator contribution");
        });

        it("Should fail to update pubkey after contract is finalized", async function () {
            // Finalize the contract
            const stakingRequirement  = await snContribution.stakingRequirement();
            await sentToken.connect(snOperator).approve(snContribution.target, stakingRequirement);
            await snContribution.connect(snOperator).contributeFunds(stakingRequirement);
            await expect(snContribution.finalize()).to.not.be.reverted;

            // Try to update pubkey after finalization
            await expect(snContribution.connect(snOperator).updatePubkeys(newNode.blsPubkey,
                                                                          newNode.blsSig,
                                                                          newNode.snParams.serviceNodePubkey,
                                                                          newNode.snParams.serviceNodeSignature1,
                                                                          newNode.snParams.serviceNodeSignature2))
                .to.be.revertedWith("Contract can not accept new public keys, already received operator contribution");
        });

        it("Should update fee after contract reset", async function () {
            // Finalize the contract
            const stakingRequirement  = await snContribution.stakingRequirement();
            await sentToken.connect(snOperator).approve(snContribution.target, stakingRequirement);
            await snContribution.connect(snOperator).contributeFunds(stakingRequirement);
            await expect(snContribution.finalize()).to.not.be.reverted;

            // Reset the contract
            await snContribution.connect(snOperator).reset();

            // Update params after reset
            await expect(snContribution.connect(snOperator).updateFee(1n))
                .to.not.be.reverted;

            const params = await snContribution.serviceNodeParams();
            expect(params.serviceNodePubkey).to.equal(oldNode.snParams.serviceNodePubkey);
            expect(params.fee).to.equal(1);
            expect(params.serviceNodeSignature1).to.deep.equal(oldNode.snParams.serviceNodeSignature1);
            expect(params.serviceNodeSignature2).to.deep.equal(oldNode.snParams.serviceNodeSignature2);
        });

        it("Should update pubkey after contract reset", async function () {
            // Finalize the contract
            const stakingRequirement  = await snContribution.stakingRequirement();
            await sentToken.connect(snOperator).approve(snContribution.target, stakingRequirement);
            await snContribution.connect(snOperator).contributeFunds(stakingRequirement);
            await expect(snContribution.finalize()).to.not.be.reverted;


            // Reset the contract
            await snContribution.connect(snOperator).reset();

            // Update pubkey after reset
            await expect(snContribution.connect(snOperator)
                                       .updatePubkeys(newNode.blsPubkey,
                                                      newNode.blsSig,
                                                      newNode.snParams.serviceNodePubkey,
                                                      newNode.snParams.serviceNodeSignature1,
                                                      newNode.snParams.serviceNodeSignature2)).to.not.be.reverted;

            const blsPubkey = await snContribution.blsPubkey();
            expect(blsPubkey.X).to.equal(newNode.blsPubkey.X);
            expect(blsPubkey.Y).to.equal(newNode.blsPubkey.Y);

            const params = await snContribution.serviceNodeParams();
            expect(params.fee).to.equal(0);
            expect(params.serviceNodePubkey).to.equal(newNode.snParams.serviceNodePubkey);
            expect(params.serviceNodeSignature1).to.equal(newNode.snParams.serviceNodeSignature1);
            expect(params.serviceNodeSignature2).to.equal(newNode.snParams.serviceNodeSignature2);
        });
    });
});
