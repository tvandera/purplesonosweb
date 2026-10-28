{ lib, fetchurl, perlPackages }:
let
  XMLLiberal = with perlPackages;
  buildPerlPackage {
    pname = "XML-Liberal";
    version = "0.32";
    src = fetchurl {
      url = "mirror://cpan/authors/id/M/MI/MIYAGAWA/XML-Liberal-0.32.tar.gz";
      hash = "sha256-qegds9fMR5DKyM5h3OWQAbPdnorM9VTwMJyP3emlK5k=";
    };
    buildInputs = [ TestBase ];
    propagatedBuildInputs = [ ClassAccessor HTMLParser HTMLTagset ModulePluggableFast UNIVERSALrequire XMLLibXML ];
    meta = {
      homepage = "https://github.com/miyagawa/XML-Liberal";
      description = "Super liberal XML parser that parses broken XML";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
    doCheck = false;
  };
  ScalarUtilNumeric = with perlPackages;
  buildPerlPackage {
    pname = "Scalar-Util-Numeric";
    version = "0.40";
    src = fetchurl {
      url = "mirror://cpan/authors/id/C/CH/CHOCOLATE/Scalar-Util-Numeric-0.40.tar.gz";
      hash = "sha256-11AbbUEHA9tbHBlC+/xBr4lko1Ul1/dmBYrPXKLMREA=";
    };
    meta = {
      description = "Numeric tests for perl scalars";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
  };
  LV = with perlPackages;
  buildPerlPackage {
    pname = "LV";
    version = "0.006";
    src = fetchurl {
      url = "mirror://cpan/authors/id/T/TO/TOBYINK/LV-0.006.tar.gz";
      hash = "sha256-+ojC1K8LESbUZAHmNVplSW0DPPwqapRGUwEaY4rfp1w=";
    };
    meta = {
      description = "Lvalue subroutines";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
  };
  JSONPath = with perlPackages;
  buildPerlPackage {
    pname = "JSON-Path";
    version = "1.0.6";
    src = fetchurl {
      url = "mirror://cpan/authors/id/P/PO/POPEFELIX/JSON-Path-1.0.6.tar.gz";
      hash = "sha256-s28/rpFZDLIKbFT4DGvmsrLWypIkeiowqrc9iGRwAv8=";
    };
    propagatedBuildInputs = [ CarpAssert ExporterTiny JSONMaybeXS LV Readonly TryTiny ];
    meta = {
      description = "Search nested Perl data structures using JSONPath";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
    doCheck = false;
  };
  ImageResize = with perlPackages;
  buildPerlPackage {
    pname = "Image-Resize";
    version = "0.5";
    src = fetchurl {
      url = "mirror://cpan/authors/id/S/SH/SHERZODR/Image-Resize-0.5.tar.gz";
      hash = "sha256-Xv6dJHygsEd+uPkVVyYVCOukwZxDRqGlq7NnxTRwbSk=";
    };
    propagatedBuildInputs = [ GD ];
    meta = {
    };
  };
  UPnPControlPoint = with perlPackages;
  buildPerlPackage {
    pname = "UPnP-ControlPoint";
    version = "0.5";
    src = fetchurl {
      url = "https://github.com/tvandera/perlupnp/archive/refs/tags/v0.5.tar.gz";
      hash = "sha256-H17s591u1uoSr+dN/aBrdFWDHWpvJ4lNrr2cDhNpMTI=";
    };
    propagatedBuildInputs = [ LWP SOAPLite HTTPDaemon XMLParserLite ];
    meta = {
    };
    doCheck = false;
  };
in

perlPackages.buildPerlPackage rec {
  pname = "Sonos";
  version = "0.90";
  src = ./..;
  propagatedBuildInputs = with perlPackages; [
      Carp DataDumper DigestSHA Encode LogLog4perl ListMoreUtils FileSlurp FileBaseDir
      HTMLParser TemplateToolkit HTTPDaemon NetAsyncHTTPServer IOCompress
      ImageResize
      IO IOAsync JSON LWPMediaTypes LWP MIMEBase64 MIMETypes FileMimeInfo SOAPLite
      Socket TimeHiRes URI XMLSimple XMLLiberal XMLLibXMLSimple JSONXS
      TextTable IOStringy ScalarUtilNumeric UPnPControlPoint
      JSONPath TryTiny TypesSerialiser HTTPMessage
  ];
  meta = {
    description = "Sonos Daemon with a REST API, Web UI and CLI";
    license = with lib.licenses; [ mit ];
  };
  doCheck = false;
}
