pub(crate) mod from_elx;
pub(crate) mod from_lh;
pub(crate) mod helpers;

macro_rules! match_schema_and_encode {
    (($schema:expr, $map:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                stringify!($t) => $crate::utils::helpers::encode_ssz::<types::$t, lh_types::$t>($map),
            )*
            _ => unreachable!(),
        }
    };
}

macro_rules! match_schema_and_decode {
    (($schema:expr, $bytes:expr, $env:expr) => { $($t:tt),* $(,)? }) => {
        match $schema {
            $(
                stringify!($t) => $crate::utils::helpers::decode_ssz::<types::$t, lh_types::$t>($bytes, $env),
            )*
            _ => unreachable!(),
        }
    };
}

macro_rules! gen_struct {
    // Named-Struct
    (
        $( #[$meta:meta] )*
    //  ^~~~attributes~~~~^
        $vis:vis struct $name:ident {
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
        $vis struct $name<'a> {
            $(
                $( #[$field_meta] )*
                $field_vis $field_name : $field_ty
            ),*
        }
        impl<'a> $crate::utils::from_lh::FromLH<'a, ::lighthouse_types::$name> for $name<'a> {
            fn from(lh: ::lighthouse_types::$name, env: ::rustler::Env<'a>) -> Self {
                $(
                    let $field_name = $crate::utils::from_lh::FromLH::from(lh.$field_name, env);
                )*
                Self {
                    $($field_name),*
                }
            }
        }

        impl $crate::utils::from_elx::FromElx<$name<'_>> for ::lighthouse_types::$name {
            fn from(elx: $name) -> Self {
                $(
                    let $field_name = $crate::utils::from_elx::FromElx::from(elx.$field_name);
                )*
                Self {
                    $($field_name),*
                }
            }
        }
    }
}

pub(crate) use gen_struct;
pub(crate) use match_schema_and_decode;
pub(crate) use match_schema_and_encode;
