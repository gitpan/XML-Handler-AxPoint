use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME' => 'XML::Handler::AxPoint',
    'VERSION_FROM' => 'lib/XML/Handler/AxPoint.pm',
    'PREREQ_PM' => {
    	PDFLib => 0.05,
    	XML::SAX => 0.09,
    	XML::SAX::Writer => 0.39,
    },
    'ABSTRACT_FROM' => 'lib/XML/Handler/AxPoint.pm',
    'AUTHOR' => 'Matt Sergeant <matt@sergeant.org>',
);
