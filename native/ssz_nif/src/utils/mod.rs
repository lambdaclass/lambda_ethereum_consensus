pub(crate) mod from_elx;
pub(crate) mod from_ssz;
pub(crate) mod helpers;

/// New containers should be added to this macro
macro_rules! schema_match {
    ($schema:expr, $config:expr, $fun:ident, $args:tt) => {
        $crate::utils::schema_match_impl!(
            ($schema, $config, $fun, $args) => {
                HistoricalSummary,
                AttestationData,
                IndexedAttestation<C>,
                Checkpoint,
                Eth1Data,
                Fork,
                ForkData,
                HistoricalBatch<C>,
                PendingAttestation<C>,
                Validator,
                DepositData,
                VoluntaryExit,
                Deposit,
                DepositMessage,
                BLSToExecutionChange,
                SignedBLSToExecutionChange,
                Attestation<C>,
                BeaconBlock<C>,
                BeaconBlockHeader,
                AttesterSlashing<C>,
                SignedBeaconBlock<C>,
                SignedBeaconBlockHeader,
                SignedVoluntaryExit,
                ProposerSlashing,
                ExecutionPayload<C>,
                ExecutionPayloadHeader<C>,
                Withdrawal,
                SigningData,
                SyncAggregate<C>,
                SyncCommittee<C>,
                SyncCommitteeMessage,
                SyncCommitteeContribution<C>,
                ContributionAndProof<C>,
                SignedContributionAndProof<C>,
                BeaconState<C>,
                BeaconBlockBody<C>,
                StatusMessage,
                AggregateAndProof<C>,
                SignedAggregateAndProof<C>,
                BeaconBlocksByRangeRequest,
                Transaction,
                Metadata<C>,
                Root,
                Epoch,
                BlobSidecar<C>,
                BlobIdentifier,
            }
        )
    };
}

macro_rules! schema_match_impl {
    (($schema:expr, $config:expr, $fun:ident, $args:tt) => { $($t:ident $(<$_c:ident>)?),* $(,)? }) => {
        match $schema {
            $(
                stringify!($t) => $crate::utils::config_match!($config, $fun, $args, $t $(<$_c>)?),
            )*
            _ => Err(rustler::Error::BadArg),
        }
    };
}

/// New configs should be added to this macro
macro_rules! config_match {
    ($config:expr, $fun:ident, $args:tt, $t:ident<C>) => {
        match $config {
            "mainnet" => $crate::utils::helpers::$fun::<
                elx_types::$t,
                ssz_types::$t<$crate::ssz_types::config::Mainnet>,
            >($args),
            "minimal" => $crate::utils::helpers::$fun::<
                elx_types::$t,
                ssz_types::$t<$crate::ssz_types::config::Minimal>,
            >($args),
            "gnosis" => $crate::utils::helpers::$fun::<
                elx_types::$t,
                ssz_types::$t<$crate::ssz_types::config::Gnosis>,
            >($args),
            _ => Err(rustler::Error::BadArg),
        }
    };
    ($config:expr, $fun:ident, $args:tt, $t:ident) => {
        match $config {
            "mainnet" | "minimal" | "gnosis" => {
                $crate::utils::helpers::$fun::<elx_types::$t, ssz_types::$t>($args)
            }
            _ => Err(rustler::Error::BadArg),
        }
    };
}

macro_rules! gen_struct_with_config {
    // Named-Struct
    (
        $( #[$meta:meta] )*
    //  ^~~~attributes~~~~^
        $vis:vis struct $name:ident$(< $( $lt:tt $( : $clt:tt $(+ $dlt:tt )* )? ),+ >)? {
            $(
                $( #[$field_meta:meta] )*
    //          ^~~~field attributes~~~!^
                $field_vis:vis $field_name:ident : $field_ty:ty
    //          ^~~~~~~~~~~~~~~~~a single field~~~~~~~~~~~~~~~^
            ),*
        $(,)? }
    ) => {
        $( #[$meta] )*
        #[derive(Clone)]
        $vis struct $name$(< $( $lt $( : $clt $(+ $dlt )* )? ),+ >)? {
            $(
                $( #[$field_meta] )*
                $field_vis $field_name : $field_ty
            ),*
        }
        impl<'a, C: $crate::ssz_types::config::Config> $crate::utils::from_ssz::FromSsz<'a, $crate::ssz_types::$name<C>> for $name$(< $( $lt $( : $clt $(+ $dlt )* )? ),+ >)? {
            fn from(ssz: $crate::ssz_types::$name<C>, env: ::rustler::Env<'a>) -> Self {
                $(
                    let $field_name = $crate::utils::from_ssz::FromSsz::from(ssz.$field_name, env);
                )*
                Self {
                    $($field_name),*
                }
            }
        }

        impl< $($( $lt $( : $clt $(+ $dlt )* )? ),+,)? C: $crate::ssz_types::config::Config>
        $crate::utils::from_elx::FromElx<$name$(< $( $lt $( : $clt $(+ $dlt )* )? ),+ >)?> for $crate::ssz_types::$name<C> {
            fn from(elx: $name) -> Result<Self, $crate::utils::from_elx::FromElxError> {
                $(
                    let $field_name = $crate::utils::from_elx::FromElx::from(elx.$field_name)?;
                )*
                Ok(Self {
                    $($field_name),*
                })
            }
        }
    }
}

macro_rules! gen_struct {
    // Named-Struct
    (
        $( #[$meta:meta] )*
    //  ^~~~attributes~~~~^
        $vis:vis struct $name:ident$(< $( $lt:tt $( : $clt:tt $(+ $dlt:tt )* )? ),+ >)? {
            $(
                $( #[$field_meta:meta] )*
    //          ^~~~field attributes~~~!^
                $field_vis:vis $field_name:ident : $field_ty:ty
    //          ^~~~~~~~~~~~~~~~~a single field~~~~~~~~~~~~~~~^
            ),*
        $(,)? }
    ) => {
        $( #[$meta] )*
        #[derive(Clone)]
        $vis struct $name$(< $( $lt $( : $clt $(+ $dlt )* )? ),+ >)? {
            $(
                $( #[$field_meta] )*
                $field_vis $field_name : $field_ty
            ),*
        }
        impl<'a> $crate::utils::from_ssz::FromSsz<'a, $crate::ssz_types::$name> for $name$(< $( $lt $( : $clt $(+ $dlt )* )? ),+ >)? {
            fn from(ssz: $crate::ssz_types::$name, env: ::rustler::Env<'a>) -> Self {
                $(
                    let $field_name = $crate::utils::from_ssz::FromSsz::from(ssz.$field_name, env);
                )*
                Self {
                    $($field_name),*
                }
            }
        }

        impl< $($( $lt $( : $clt $(+ $dlt )* )? ),+)?>
        $crate::utils::from_elx::FromElx<$name$(< $( $lt $( : $clt $(+ $dlt )* )? ),+ >)?> for $crate::ssz_types::$name {
            fn from(elx: $name) -> Result<Self, $crate::utils::from_elx::FromElxError> {
                $(
                    let $field_name = $crate::utils::from_elx::FromElx::from(elx.$field_name)?;
                )*
                Ok(Self {
                    $($field_name),*
                })
            }
        }
    }
}

pub(crate) use config_match;
pub(crate) use schema_match;
pub(crate) use schema_match_impl;

pub(crate) use gen_struct;
pub(crate) use gen_struct_with_config;
