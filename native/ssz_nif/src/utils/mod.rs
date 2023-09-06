pub(crate) mod from_elx;
pub(crate) mod from_ssz;
pub(crate) mod helpers;

macro_rules! match_schema_and_encode {
    (($schema:expr, $config:expr, $map:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                stringify!($t) => match $config {
                    "MainnetConfig" => $crate::utils::helpers::encode_ssz::<
                        elx_types::$t, ssz_types::$t<
                            $crate::ssz_types::config::Mainnet
                        >>($map),
                    "MinimalConfig" => $crate::utils::helpers::encode_ssz::<
                    elx_types::$t, ssz_types::$t<
                        $crate::ssz_types::config::Minimal
                    >>($map),
                    _ => Err(rustler::Error::BadArg),
                }
            )*
            _ => Err(rustler::Error::BadArg),
        }
    };
}

macro_rules! match_schema_and_decode {
    (($schema:expr, $config:expr, $bytes:expr, $env:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                stringify!($t) => match $config {
                    "MainnetConfig" => $crate::utils::helpers::decode_ssz::<
                        elx_types::$t, ssz_types::$t<
                            $crate::ssz_types::config::Mainnet
                        >>($bytes, $env),
                    "MinimalConfig" => $crate::utils::helpers::decode_ssz::<
                    elx_types::$t, ssz_types::$t<
                        $crate::ssz_types::config::Minimal
                    >>($bytes, $env),
                    _ => Err(rustler::Error::BadArg),
                }
            )*
            _ => Err(rustler::Error::BadArg),
        }
    };
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

        impl< $($( $lt $( : $clt $(+ $dlt )* )? ),+)?, C: $crate::ssz_types::config::Config>
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

pub(crate) use gen_struct;
pub(crate) use match_schema_and_decode;
pub(crate) use match_schema_and_encode;
