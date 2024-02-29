// Taken from lighthouse

use ssz_types::typenum::{self, *};

pub type U5000 = UInt<UInt<UInt<U625, B0>, B0>, B0>; // 625 * 8 = 5000

/// Macro to inherit some type values from another `Config`.
#[macro_export]
macro_rules! inherit_from {
    ($spec_ty:ty { $($ty_name:ident),+ }) => {
        $(type $ty_name = <$spec_ty as Config>::$ty_name;)+
    }
}

pub(crate) trait Config {
    type JustificationBitsLength: Unsigned;
    type SubnetBitfieldLength: Unsigned;
    type MaxValidatorsPerCommittee: Unsigned;
    type GenesisEpoch: Unsigned;
    type SlotsPerEpoch: Unsigned;
    type EpochsPerEth1VotingPeriod: Unsigned;
    type SlotsPerHistoricalRoot: Unsigned;
    type EpochsPerHistoricalVector: Unsigned;
    type EpochsPerSlashingsVector: Unsigned;
    type HistoricalRootsLimit: Unsigned;
    type ValidatorRegistryLimit: Unsigned;
    type MaxProposerSlashings: Unsigned;
    type MaxAttesterSlashings: Unsigned;
    type MaxAttestations: Unsigned;
    type MaxDeposits: Unsigned;
    type MaxVoluntaryExits: Unsigned;
    type SyncCommitteeSize: Unsigned;
    type SyncCommitteeSubnetCount: Unsigned;
    type AttestationSubnetCount: Unsigned;
    type MaxBytesPerTransaction: Unsigned;
    type MaxTransactionsPerPayload: Unsigned;
    type BytesPerLogsBloom: Unsigned;
    type GasLimitDenominator: Unsigned;
    type MinGasLimit: Unsigned;
    type MaxExtraDataBytes: Unsigned;
    type MaxBlsToExecutionChanges: Unsigned;
    type MaxWithdrawalsPerPayload: Unsigned;
    /*
     * New in Deneb
     */
    type MaxBlobsPerBlock: Unsigned;
    type MaxBlobCommitmentsPerBlock: Unsigned;
    type FieldElementsPerBlob: Unsigned;
    type BytesPerFieldElement: Unsigned;
    type KzgCommitmentInclusionProofDepth: Unsigned;

    // Derived constants. Ideally, this would be trait defaults.
    type SyncSubcommitteeSize: Unsigned; // SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
    type MaxPendingAttestations: Unsigned; // MAX_ATTESTATIONS * SLOTS_PER_EPOCH
    type SlotsPerEth1VotingPeriod: Unsigned; // EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
    type BytesPerBlob: Unsigned; // FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT
}

pub(crate) struct Mainnet;

impl Config for Mainnet {
    type JustificationBitsLength = U4;
    type SubnetBitfieldLength = U64;
    type MaxValidatorsPerCommittee = U2048;
    type GenesisEpoch = U0;
    type SlotsPerEpoch = U32;
    type EpochsPerEth1VotingPeriod = U64;
    type SlotsPerHistoricalRoot = U8192;
    type EpochsPerHistoricalVector = U65536;
    type EpochsPerSlashingsVector = U8192;
    type HistoricalRootsLimit = U16777216;
    type ValidatorRegistryLimit = U1099511627776;
    type MaxProposerSlashings = U16;
    type MaxAttesterSlashings = U2;
    type MaxAttestations = U128;
    type MaxDeposits = U16;
    type MaxVoluntaryExits = U16;
    type SyncCommitteeSize = U512;
    type SyncCommitteeSubnetCount = U4;
    type AttestationSubnetCount = U64;
    type MaxBytesPerTransaction = U1073741824; // 1,073,741,824
    type MaxTransactionsPerPayload = U1048576; // 1,048,576
    type BytesPerLogsBloom = U256;
    type GasLimitDenominator = U1024;
    type MinGasLimit = U5000;
    type MaxExtraDataBytes = U32;
    type MaxBlsToExecutionChanges = U16;
    type MaxWithdrawalsPerPayload = U16;
    type MaxBlobsPerBlock = U6;
    type MaxBlobCommitmentsPerBlock = U4096;
    type FieldElementsPerBlob = U4096;
    type BytesPerFieldElement = U32;
    type KzgCommitmentInclusionProofDepth = U17;

    // Derived constants. Ideally, this would be trait defaults.
    type SyncSubcommitteeSize =
        typenum::Quot<Self::SyncCommitteeSize, Self::SyncCommitteeSubnetCount>; // 512 committee size / 4 sync committee subnet count
    type MaxPendingAttestations = typenum::Prod<Self::MaxAttestations, Self::SlotsPerEpoch>; // 128 max attestations * 32 slots per epoch
    type SlotsPerEth1VotingPeriod =
        typenum::Prod<Self::EpochsPerEth1VotingPeriod, Self::SlotsPerEpoch>; // 64 epochs * 32 slots per epoch
    type BytesPerBlob = typenum::Prod<Self::FieldElementsPerBlob, Self::BytesPerFieldElement>;
}

pub(crate) struct Minimal;

impl Config for Minimal {
    type SlotsPerEpoch = U8;
    type EpochsPerEth1VotingPeriod = U4;
    type SlotsPerHistoricalRoot = U64;
    type EpochsPerHistoricalVector = U64;
    type EpochsPerSlashingsVector = U64;
    type SyncCommitteeSize = U32;
    type MaxWithdrawalsPerPayload = U4;
    type FieldElementsPerBlob = U4096;
    type MaxBlobCommitmentsPerBlock = U16;
    type KzgCommitmentInclusionProofDepth = U9;

    // Derived constants. Ideally, this would be trait defaults.
    type SyncSubcommitteeSize =
        typenum::Quot<Self::SyncCommitteeSize, Self::SyncCommitteeSubnetCount>; // 32 committee size / 4 sync committee subnet count
    type MaxPendingAttestations = typenum::Prod<Self::MaxAttestations, Self::SlotsPerEpoch>; // 128 max attestations * 8 slots per epoch
    type SlotsPerEth1VotingPeriod =
        typenum::Prod<Self::EpochsPerEth1VotingPeriod, Self::SlotsPerEpoch>; // 4 epochs * 8 slots per epoch
    type BytesPerBlob = typenum::Prod<Self::FieldElementsPerBlob, Self::BytesPerFieldElement>;

    inherit_from!(Mainnet {
        JustificationBitsLength,
        SubnetBitfieldLength,
        SyncCommitteeSubnetCount,
        AttestationSubnetCount,
        MaxValidatorsPerCommittee,
        GenesisEpoch,
        HistoricalRootsLimit,
        ValidatorRegistryLimit,
        MaxProposerSlashings,
        MaxAttesterSlashings,
        MaxAttestations,
        MaxDeposits,
        MaxVoluntaryExits,
        MaxBytesPerTransaction,
        MaxTransactionsPerPayload,
        BytesPerLogsBloom,
        GasLimitDenominator,
        MinGasLimit,
        MaxExtraDataBytes,
        MaxBlsToExecutionChanges,
        MaxBlobsPerBlock,
        BytesPerFieldElement
    });
}

pub(crate) struct Gnosis;

impl Config for Gnosis {
    type JustificationBitsLength = U4;
    type SubnetBitfieldLength = U64;
    type MaxValidatorsPerCommittee = U2048;
    type GenesisEpoch = U0;
    type SlotsPerEpoch = U16;
    type EpochsPerEth1VotingPeriod = U64;
    type SlotsPerHistoricalRoot = U8192;
    type EpochsPerHistoricalVector = U65536;
    type EpochsPerSlashingsVector = U8192;
    type HistoricalRootsLimit = U16777216;
    type ValidatorRegistryLimit = U1099511627776;
    type MaxProposerSlashings = U16;
    type MaxAttesterSlashings = U2;
    type MaxAttestations = U128;
    type MaxDeposits = U16;
    type MaxVoluntaryExits = U16;
    type SyncCommitteeSize = U512;
    type SyncCommitteeSubnetCount = U4;
    type AttestationSubnetCount = U64;
    type MaxBytesPerTransaction = U1073741824; // 1,073,741,824
    type MaxTransactionsPerPayload = U1048576; // 1,048,576
    type BytesPerLogsBloom = U256;
    type GasLimitDenominator = U1024;
    type MinGasLimit = U5000;
    type MaxExtraDataBytes = U32;
    type MaxBlsToExecutionChanges = U16;
    type MaxWithdrawalsPerPayload = U8;
    type MaxBlobsPerBlock = U6;
    type MaxBlobCommitmentsPerBlock = U4096;
    type FieldElementsPerBlob = U4096;
    type BytesPerFieldElement = U32;
    type KzgCommitmentInclusionProofDepth = U17;

    // Derived constants. Ideally, this would be trait defaults.
    type SyncSubcommitteeSize =
        typenum::Quot<Self::SyncCommitteeSize, Self::SyncCommitteeSubnetCount>; // 512 committee size / 4 sync committee subnet count
    type MaxPendingAttestations = typenum::Prod<Self::MaxAttestations, Self::SlotsPerEpoch>; // 128 max attestations * 32 slots per epoch
    type SlotsPerEth1VotingPeriod =
        typenum::Prod<Self::EpochsPerEth1VotingPeriod, Self::SlotsPerEpoch>; // 64 epochs * 32 slots per epoch
    type BytesPerBlob = typenum::Prod<Self::FieldElementsPerBlob, Self::BytesPerFieldElement>;
}
