use std::io::Write;

use rustler::{Binary, Env, NewBinary};

pub(crate) mod from_elx;
pub(crate) mod from_lh;

pub(crate) fn bytes_to_binary<'env>(env: Env<'env>, bytes: &[u8]) -> Binary<'env> {
    let mut binary = NewBinary::new(env, bytes.len());
    // This cannot fail because bin size equals bytes len
    binary.as_mut_slice().write_all(bytes).unwrap();
    binary.into()
}

#[macro_export]
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

        impl From<$name<'_>> for ::lighthouse_types::$name {
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
