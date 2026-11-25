// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ScanError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ScanError()';
}


}

/// @nodoc
class $ScanErrorCopyWith<$Res>  {
$ScanErrorCopyWith(ScanError _, $Res Function(ScanError) __);
}


/// Adds pattern-matching-related methods to [ScanError].
extension ScanErrorPatterns on ScanError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ScanError_Io value)?  io,TResult Function( ScanError_Image value)?  image,TResult Function( ScanError_InvalidQuad value)?  invalidQuad,TResult Function( ScanError_Pdf value)?  pdf,TResult Function( ScanError_EncryptedPdf value)?  encryptedPdf,TResult Function( ScanError_Zip value)?  zip,TResult Function( ScanError_InvalidArgument value)?  invalidArgument,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ScanError_Io() when io != null:
return io(_that);case ScanError_Image() when image != null:
return image(_that);case ScanError_InvalidQuad() when invalidQuad != null:
return invalidQuad(_that);case ScanError_Pdf() when pdf != null:
return pdf(_that);case ScanError_EncryptedPdf() when encryptedPdf != null:
return encryptedPdf(_that);case ScanError_Zip() when zip != null:
return zip(_that);case ScanError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ScanError_Io value)  io,required TResult Function( ScanError_Image value)  image,required TResult Function( ScanError_InvalidQuad value)  invalidQuad,required TResult Function( ScanError_Pdf value)  pdf,required TResult Function( ScanError_EncryptedPdf value)  encryptedPdf,required TResult Function( ScanError_Zip value)  zip,required TResult Function( ScanError_InvalidArgument value)  invalidArgument,}){
final _that = this;
switch (_that) {
case ScanError_Io():
return io(_that);case ScanError_Image():
return image(_that);case ScanError_InvalidQuad():
return invalidQuad(_that);case ScanError_Pdf():
return pdf(_that);case ScanError_EncryptedPdf():
return encryptedPdf(_that);case ScanError_Zip():
return zip(_that);case ScanError_InvalidArgument():
return invalidArgument(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ScanError_Io value)?  io,TResult? Function( ScanError_Image value)?  image,TResult? Function( ScanError_InvalidQuad value)?  invalidQuad,TResult? Function( ScanError_Pdf value)?  pdf,TResult? Function( ScanError_EncryptedPdf value)?  encryptedPdf,TResult? Function( ScanError_Zip value)?  zip,TResult? Function( ScanError_InvalidArgument value)?  invalidArgument,}){
final _that = this;
switch (_that) {
case ScanError_Io() when io != null:
return io(_that);case ScanError_Image() when image != null:
return image(_that);case ScanError_InvalidQuad() when invalidQuad != null:
return invalidQuad(_that);case ScanError_Pdf() when pdf != null:
return pdf(_that);case ScanError_EncryptedPdf() when encryptedPdf != null:
return encryptedPdf(_that);case ScanError_Zip() when zip != null:
return zip(_that);case ScanError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  io,TResult Function( String field0)?  image,TResult Function()?  invalidQuad,TResult Function( String field0)?  pdf,TResult Function()?  encryptedPdf,TResult Function( String field0)?  zip,TResult Function( String field0)?  invalidArgument,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ScanError_Io() when io != null:
return io(_that.field0);case ScanError_Image() when image != null:
return image(_that.field0);case ScanError_InvalidQuad() when invalidQuad != null:
return invalidQuad();case ScanError_Pdf() when pdf != null:
return pdf(_that.field0);case ScanError_EncryptedPdf() when encryptedPdf != null:
return encryptedPdf();case ScanError_Zip() when zip != null:
return zip(_that.field0);case ScanError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  io,required TResult Function( String field0)  image,required TResult Function()  invalidQuad,required TResult Function( String field0)  pdf,required TResult Function()  encryptedPdf,required TResult Function( String field0)  zip,required TResult Function( String field0)  invalidArgument,}) {final _that = this;
switch (_that) {
case ScanError_Io():
return io(_that.field0);case ScanError_Image():
return image(_that.field0);case ScanError_InvalidQuad():
return invalidQuad();case ScanError_Pdf():
return pdf(_that.field0);case ScanError_EncryptedPdf():
return encryptedPdf();case ScanError_Zip():
return zip(_that.field0);case ScanError_InvalidArgument():
return invalidArgument(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  io,TResult? Function( String field0)?  image,TResult? Function()?  invalidQuad,TResult? Function( String field0)?  pdf,TResult? Function()?  encryptedPdf,TResult? Function( String field0)?  zip,TResult? Function( String field0)?  invalidArgument,}) {final _that = this;
switch (_that) {
case ScanError_Io() when io != null:
return io(_that.field0);case ScanError_Image() when image != null:
return image(_that.field0);case ScanError_InvalidQuad() when invalidQuad != null:
return invalidQuad();case ScanError_Pdf() when pdf != null:
return pdf(_that.field0);case ScanError_EncryptedPdf() when encryptedPdf != null:
return encryptedPdf();case ScanError_Zip() when zip != null:
return zip(_that.field0);case ScanError_InvalidArgument() when invalidArgument != null:
return invalidArgument(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ScanError_Io extends ScanError {
  const ScanError_Io(this.field0): super._();
  

 final  String field0;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanError_IoCopyWith<ScanError_Io> get copyWith => _$ScanError_IoCopyWithImpl<ScanError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanError_IoCopyWith<$Res> implements $ScanErrorCopyWith<$Res> {
  factory $ScanError_IoCopyWith(ScanError_Io value, $Res Function(ScanError_Io) _then) = _$ScanError_IoCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ScanError_IoCopyWithImpl<$Res>
    implements $ScanError_IoCopyWith<$Res> {
  _$ScanError_IoCopyWithImpl(this._self, this._then);

  final ScanError_Io _self;
  final $Res Function(ScanError_Io) _then;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ScanError_Image extends ScanError {
  const ScanError_Image(this.field0): super._();
  

 final  String field0;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanError_ImageCopyWith<ScanError_Image> get copyWith => _$ScanError_ImageCopyWithImpl<ScanError_Image>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_Image&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanError.image(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanError_ImageCopyWith<$Res> implements $ScanErrorCopyWith<$Res> {
  factory $ScanError_ImageCopyWith(ScanError_Image value, $Res Function(ScanError_Image) _then) = _$ScanError_ImageCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ScanError_ImageCopyWithImpl<$Res>
    implements $ScanError_ImageCopyWith<$Res> {
  _$ScanError_ImageCopyWithImpl(this._self, this._then);

  final ScanError_Image _self;
  final $Res Function(ScanError_Image) _then;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanError_Image(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ScanError_InvalidQuad extends ScanError {
  const ScanError_InvalidQuad(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_InvalidQuad);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ScanError.invalidQuad()';
}


}




/// @nodoc


class ScanError_Pdf extends ScanError {
  const ScanError_Pdf(this.field0): super._();
  

 final  String field0;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanError_PdfCopyWith<ScanError_Pdf> get copyWith => _$ScanError_PdfCopyWithImpl<ScanError_Pdf>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_Pdf&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanError.pdf(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanError_PdfCopyWith<$Res> implements $ScanErrorCopyWith<$Res> {
  factory $ScanError_PdfCopyWith(ScanError_Pdf value, $Res Function(ScanError_Pdf) _then) = _$ScanError_PdfCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ScanError_PdfCopyWithImpl<$Res>
    implements $ScanError_PdfCopyWith<$Res> {
  _$ScanError_PdfCopyWithImpl(this._self, this._then);

  final ScanError_Pdf _self;
  final $Res Function(ScanError_Pdf) _then;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanError_Pdf(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ScanError_EncryptedPdf extends ScanError {
  const ScanError_EncryptedPdf(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_EncryptedPdf);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ScanError.encryptedPdf()';
}


}




/// @nodoc


class ScanError_Zip extends ScanError {
  const ScanError_Zip(this.field0): super._();
  

 final  String field0;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanError_ZipCopyWith<ScanError_Zip> get copyWith => _$ScanError_ZipCopyWithImpl<ScanError_Zip>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_Zip&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanError.zip(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanError_ZipCopyWith<$Res> implements $ScanErrorCopyWith<$Res> {
  factory $ScanError_ZipCopyWith(ScanError_Zip value, $Res Function(ScanError_Zip) _then) = _$ScanError_ZipCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ScanError_ZipCopyWithImpl<$Res>
    implements $ScanError_ZipCopyWith<$Res> {
  _$ScanError_ZipCopyWithImpl(this._self, this._then);

  final ScanError_Zip _self;
  final $Res Function(ScanError_Zip) _then;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanError_Zip(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ScanError_InvalidArgument extends ScanError {
  const ScanError_InvalidArgument(this.field0): super._();
  

 final  String field0;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanError_InvalidArgumentCopyWith<ScanError_InvalidArgument> get copyWith => _$ScanError_InvalidArgumentCopyWithImpl<ScanError_InvalidArgument>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanError_InvalidArgument&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanError.invalidArgument(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanError_InvalidArgumentCopyWith<$Res> implements $ScanErrorCopyWith<$Res> {
  factory $ScanError_InvalidArgumentCopyWith(ScanError_InvalidArgument value, $Res Function(ScanError_InvalidArgument) _then) = _$ScanError_InvalidArgumentCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ScanError_InvalidArgumentCopyWithImpl<$Res>
    implements $ScanError_InvalidArgumentCopyWith<$Res> {
  _$ScanError_InvalidArgumentCopyWithImpl(this._self, this._then);

  final ScanError_InvalidArgument _self;
  final $Res Function(ScanError_InvalidArgument) _then;

/// Create a copy of ScanError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanError_InvalidArgument(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
