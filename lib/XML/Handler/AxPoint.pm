# $Id: AxPoint.pm,v 1.10 2002/02/14 17:27:58 matt Exp $

package XML::Handler::AxPoint;
use strict;

use XML::SAX::Writer;
use PDFLib 0.09;

use vars qw($VERSION);
$VERSION = '0.03';

sub new {
    my $class = shift;
    my $opt   = (@_ == 1)  ? { %{shift()} } : {@_};
    
    $opt->{Output} ||= *{STDOUT}{IO};

    return bless $opt, $class;
}

sub set_document_locator {
    my ($self, $locator) = @_;
    $self->{locator} = $locator;
}

sub start_document {
    my ($self, $doc) = @_;

    # setup consumer
    my $ref = ref $self->{Output};
    if ($ref eq 'SCALAR') {
        $self->{Consumer} = XML::SAX::Writer::StringConsumer->new($self->{Output});
    }
    elsif ($ref eq 'ARRAY') {
        $self->{Consumer} = XML::SAX::Writer::ArrayConsumer->new($self->{Output});
    }
    elsif ($ref eq 'GLOB' or UNIVERSAL::isa($self->{Output}, 'IO::Handle')) {
        $self->{Consumer} = XML::SAX::Writer::HandleConsumer->new($self->{Output});
    }
    elsif (not $ref) {
        $self->{Consumer} = XML::SAX::Writer::FileConsumer->new($self->{Output});
    }
    elsif (UNIVERSAL::can($self->{Output}, 'output')) {
        $self->{Consumer} = $self->{Output};
    }
    else {
        XML::SAX::Writer::Exception->throw({ Message => 'Unknown option for Output' });
    }

    $self->{Encoder} = XML::SAX::Writer::NullConverter->new;

    # create PDF and set defaults
    $self->{pdf} = PDFLib->new();
    $self->{pdf}->papersize("slides");
    $self->{pdf}->set_border_style("solid", 0);

    $self->{headline_font} = "Helvetica";
    $self->{headline_size} = 18.0;

    $self->{title_font} = "Helvetica-Bold";
    $self->{title_size} = 24.0;

    $self->{subtitle_font} = "Helvetica-Bold";
    $self->{subtitle_size} = 20.0;
    
    $self->{todo} = [];
    $self->{bookmarks} = [];
}

sub run_todo {
    my $self = shift;

    while (my $todo = shift(@{$self->{todo}})) {
        $todo->();
    }
}

sub push_todo {
    my $self = shift;

    push @{$self->{todo}}, shift;
}

sub push_bookmark {
    my $self = shift;
    # warn("push_bookmark($_[0]) from ", caller, "\n");
    push @{$self->{bookmarks}}, shift;
}

sub top_bookmark {
    my $self = shift;
    return $self->{bookmarks}[-1];
}

sub pop_bookmark {
    my $self = shift;
    # warn("pop_bookmark() from ", caller, "\n");
    pop @{$self->{bookmarks}};
}

sub end_document {
    my ($self) = @_;

    $self->{pdf}->finish;

    $self->{Consumer}->output( $self->{pdf}->get_buffer );
    $self->{Consumer}->finalize;
}

sub new_page {
    my $self = shift;
    my ($trans) = @_;

    $self->{pdf}->start_page;

    my $transition = $trans || $self->get_transition || 'replace';

    $self->{pdf}->set_parameter(transition => lc($transition));

    if (my $bg = $self->{bg}) {
        $self->{pdf}->add_image(img => $bg->{image}, x => 0, y => 0, scale => $bg->{scale});
    }

    if (my $logo = $self->{logo}) {
        my $logo_w = $logo->{image}->width * $logo->{scale};
        $self->{pdf}->add_image(img => $logo->{image}, x => 612 - $logo_w, y => 0, scale => $logo->{scale});
    }

    $self->{pdf}->set_font(face => $self->{headline_font}, size => $self->{headline_size});

    $self->{xindent} = [];

    $self->{pdf}->set_text_pos(80, 300);
}

sub get_node_transition {
    my $self = shift;
    my ($node) = @_;

    if (exists($node->{Attributes}{"{}transition"})) {
        return $node->{Attributes}{"{}transition"}{Value};
    }
    return;
}

sub get_transition {
    my $self = shift;

    my $node = $self->{SlideCurrent} || $self->{Current};

    my $transition;
    while ($node && !($transition = $self->get_node_transition($node))) {
        $node = $node->{Parent};
    }
    return $transition;
}

sub playback_cache {
    my $self = shift;
    $self->{cache_trash} = [];

    while (@{$self->{cache}}) {
        my $thing = shift @{$self->{cache}};
        my ($method, $node) = @$thing;
        $self->$method($node);
        push @{$self->{cache_trash}}, $thing;
    }

    delete $self->{cache_trash};
}

sub start_element {
    my ($self, $el) = @_;

    my $parent = $el->{Parent} = $self->{Current};
    $self->{Current} = $el;

    if ($self->{cache_until}) {
        push @{$self->{cache}}, ["slide_start_element", $el];
    }

    my $name = $el->{LocalName};
    if ($name eq 'slideshow') {
        $self->push_todo(sub { $self->new_page });
    }
    elsif ($name eq 'title') {
        $self->gathered_text; # reset
    }
    elsif ($name eq 'metadata') {
    }
    elsif ($name eq 'speaker') {
        $self->gathered_text; # reset
    }
    elsif ($name eq 'email') {
        $self->gathered_text; # reset
    }
    elsif ($name eq 'organisation') {
        $self->gathered_text; # reset
    }
    elsif ($name eq 'link') {
        $self->gathered_text; # reset
    }
    elsif ($name eq 'logo') {
        if (exists($el->{Attributes}{"{}scale"})) {
            $self->{logo}{scale} = $el->{Attributes}{"{}scale"}{Value};
        }
        $self->{logo}{scale} ||= 1.0;
        $self->gathered_text; # reset
    }
    elsif ($name eq 'background') {
        if (exists($el->{Attributes}{"{}scale"})) {
            $self->{bg}{scale} = $el->{Attributes}{"{}scale"}{Value};
        }
        $self->{bg}{scale} ||= 1.0;
        $self->gathered_text; # reset
    }
    elsif ($name eq 'slideset') {
        $self->run_todo;
        $self->new_page;
    }
    elsif ($name eq 'subtitle') {
    }
    elsif ($name eq 'slide') {
        $self->run_todo; # might need to create slideset here.
        $self->{pdf}->end_page;

        $self->{images} = [];
        # cache these events now...
        $self->{cache_until} = $el->{Name};
        $self->{cache} = [["slide_start_element", $el]];
    }
    elsif ($name eq 'point') {
    }
    elsif ($name eq 'source_code' || $name eq 'source-code') {
    }
    elsif ($name eq 'image') {
        $self->gathered_text;
    }
    elsif ($name eq 'i' || $name eq 'b') {
    }
    elsif ($name eq 'colour' || $name eq 'color') {
    }
    else {
        warn("Unknown tag: $name");
    }
}

sub end_element {
    my ($self, $el) = @_;

    $el = $self->{Current};
    my $parent = $self->{Current} = $el->{Parent};

    if ($self->{cache_until}) {
        push @{$self->{cache}}, ["slide_end_element", $el];
        if ($el->{Name} eq $self->{cache_until}) {
            delete $self->{cache_until};
            return $self->playback_cache;
        }
    }

    my $name = $el->{LocalName};
    if ($name eq 'slideshow') {
        $self->run_todo;
        $self->pop_bookmark;
    }
    elsif ($name eq 'title') {
        if ($parent->{LocalName} eq 'slideshow') {
            my $title = $self->gathered_text;
            $self->push_todo(sub {
                $self->{pdf}->set_font(face => $self->{title_font}, size => $self->{title_size});

                $self->push_bookmark( $self->{pdf}->add_bookmark(text => "Title", open => 1) );

                $self->{pdf}->print_boxed($title,
                    x => 20, y => 50, w => 570, h => 300, mode => "center");

                $self->{pdf}->print_line("") for (1..4);

                my ($x, $y) = $self->{pdf}->get_text_pos();

                $self->{pdf}->set_font(face => $self->{subtitle_font}, size => $self->{subtitle_size});

                # speaker
                if ($self->{metadata}{speaker}) {
                    $self->{pdf}->add_link(link => "mailto:" . $self->{metadata}{email},
                        x => 20, y => $y - 10, w => 570, h => 24);
                    $self->{pdf}->print_boxed($self->{metadata}{speaker},
                        x => 20, y => 40, w => 570, h => $y - 24, mode => "center");
                }

                $self->{pdf}->print_line("");
                (undef, $y) = $self->{pdf}->get_text_pos();

                # organisation
                if ($self->{metadata}{organisation}) {
                    $self->{pdf}->add_link(link => $self->{metadata}{link},
                        x => 20, y => $y - 10, w => 570, h => 24);
                    $self->{pdf}->print_boxed($self->{metadata}{organisation},
                        x => 20, y => 40, w => 570, h => $y - 24, mode => "center");
                }
            });
        }
        elsif ($parent->{LocalName} eq 'slideset') {
            my $title = $self->gathered_text;

            $self->push_bookmark(
                $self->{pdf}->add_bookmark(
                    text => $title,
                    level => 2,
                    parent_of => $self->top_bookmark,
                    open => 1,
                )
            );

            $self->{pdf}->set_font(face => $self->{title_font}, size => $self->{title_size});
            $self->{pdf}->print_boxed($title,
                x => 20, y => 50, w => 570, h => 200, mode => "center");

            my ($x, $y) = $self->{pdf}->get_text_pos();
            $self->{pdf}->add_link(link => $el->{Attributes}{"{}href"}{Value},
                x => 20, y => $y - 5, w => 570, h => 24) if exists($el->{Attributes}{"{}href"});
        }
    }
    elsif ($name eq 'metadata') {
        $self->run_todo;
    }
    elsif ($name eq 'speaker') {
        $self->{metadata}{speaker} = $self->gathered_text;
    }
    elsif ($name eq 'email') {
        $self->{metadata}{email} = $self->gathered_text;
    }
    elsif ($name eq 'organisation') {
        $self->{metadata}{organisation} = $self->gathered_text;
    }
    elsif ($name eq 'link') {
        $self->{metadata}{link} = $self->gathered_text;
    }
    elsif ($name eq 'logo') {
        my $logo_file = $self->gathered_text;
        my $type = get_filetype($logo_file);
        my $logo = $self->{pdf}->load_image(
                filename => $logo_file,
                filetype => $type,
            );
        if (!$logo) {
            $self->{pdf}->finish;
            die "Cannot load image $logo_file!";
        }
        $self->{logo}{image} = $logo;
    }
    elsif ($name eq 'background') {
        my $bg_file = $self->gathered_text;
        my $type = get_filetype($bg_file);
        my $bg = $self->{pdf}->load_image(
                filename => $bg_file,
                filetype => $type,
            );
        if (!$bg) {
            $self->{pdf}->finish;
            die "Cannot load image $bg_file!";
        }
        $self->{bg}{image} = $bg;
    }
    elsif ($name eq 'slideset') {
        $self->pop_bookmark;
    }
    elsif ($name eq 'subtitle') {
        if ($parent->{LocalName} eq 'slideset') {
            $self->{pdf}->set_font(face => $self->{subtitle_font}, size => $self->{subtitle_size});
            $self->{pdf}->print_boxed($self->gathered_text,
                x => 20, y => 20, w => 570, h => 200, mode => "center");
            if (exists($el->{Attributes}{"{}href"})) {
                my ($x, $y) = $self->{pdf}->get_text_pos();
                $self->{pdf}->add_link(link => $el->{Attributes}{"{}href"}{Value},
                    x => 20, y => $y - 5, w => 570, h => 18);
            }
        }
    }
    elsif ($name eq 'slide') {
        $self->run_todo;
    }
    elsif ($name eq 'image') {
        my $image = $self->gathered_text;
        my $image_ref = $self->{pdf}->load_image(
                filename => $image,
                filetype => get_filetype($image),
            );
        my $scale = $el->{Attributes}{"{}scale"}{Value} || 1.0;
        my $href = $el->{Attributes}{"{}href"}{Value};
        push @{$self->{images}}, [$scale, $image_ref, $href];
    }

    $self->{Current} = $parent;
}

sub characters {
    my ($self, $chars) = @_;

    if ($self->{cache_until}) {
        push @{$self->{cache}}, ["slide_characters", $chars];
    }

    $self->{gathered_text} .= $chars->{Data};
}

sub invalid_parent {
    my $self = shift;
    warn("Invalid tag nesting: <$self->{Current}{Parent}{LocalName}> <$self->{Current}{LocalName}>");
}

sub gathered_text {
    my $self = shift;
    return substr($self->{gathered_text}, 0, length($self->{gathered_text}), '');
}

sub image {
    my ($pdf, $scale, $file_handle, $href) = @_;

    $pdf->print_line("");

    my ($x, $y) = $pdf->get_text_pos;
    
    my ($imgw, $imgh) = (
            $pdf->get_value("imagewidth", $file_handle->img),
            $pdf->get_value("imageheight", $file_handle->img)
            );
    
    $imgw *= $scale;
    $imgh *= $scale;
    
    $pdf->add_image(img => $file_handle,
            x => (612 / 2) - ($imgw / 2),
            y => ($y - $imgh),
            scale => $scale);
    $pdf->add_link(link => $href, x => 20, y => $y - $imgh, w => 570, h => $imgh) if $href;

    $pdf->set_text_pos($x, $y - $imgh);
}

sub bullet {
    my ($self, $level) = @_;

    my $pdf = $self->{pdf};

    my ($char, $size);
    if ($level == 1) {
        $char = "l";
        $size = 18;
    }
    elsif ($level == 2) {
        $char = "u";
        $size = 16;
    }
    elsif ($level == 3) {
        $char = "p";
        $size = 14;
    }

    if ($level == 1) {
        my ($x, $y) = $pdf->get_text_pos;
        $y += 9;
        $pdf->set_text_pos($x, $y);
        $pdf->print_line("");
    }

    my ($x, $y) = $pdf->get_text_pos;

    if (!@{$self->{xindent}} || $level > $self->{xindent}[0]{level}) {
        unshift @{$self->{xindent}}, {level => $level, x => $x};
    }

    $pdf->set_font(face => "ZapfDingbats", size => $size - 4, encoding => "builtin");
    $pdf->print($char);
    $pdf->set_font(face => "Helvetica", size => $size);
    $pdf->print("   ");
    return $size;
}

sub get_filetype {
    my $filename = shift;

    my ($suffix) = $filename =~ /([^\.]+)$/;
    $suffix = lc($suffix);
    if ($suffix eq 'jpg') {
        return 'jpeg';
    }
    return $suffix;
}

my %colours = (
    black => "000000",
    green => "008000",
    silver => "C0C0C0",
    lime => "00FF00",
    gray => "808080",
    olive => "808000",
    white => "FFFFFF",
    yellow => "FFFF00",
    maroon => "800000",
    navy => "000080",
    red => "FF0000",
    blue => "0000FF",
    purple => "800080",
    teal => "008080",
    fuchsia => "FF00FF",
    aqua => "00FFFF",
);

sub slide_start_element {
    my ($self, $el) = @_;

    $self->{SlideCurrent} = $el;

    my $name = $el->{LocalName};

    # transitions...
    if ($name eq 'point' || $name eq 'image' || $name eq 'source_code' || $name eq 'source-code') {
        if (exists($el->{Attributes}{"{}transition"})) {
            # has a transition
            my $trans = delete $el->{Attributes}{"{}transition"};
            my @cache = @{$self->{cache_trash}};
            local $self->{cache} = \@cache;
            local $self->{cache_trash};
            # warn("playback on $el\n");
            $self->{transitional} = 1;
            local $el->{Parent}{Attributes}{"{}transition"}{Value} = $trans->{Value};
            $self->playback_cache; # should get us back here.
            $self->run_todo;
            # warn("playback returns\n");
            $self->{transitional} = 0;
        }
    }

    if ($name eq 'slide') {
        $self->new_page;
        $self->{image_id} = 0;
        $self->{spot_colours} = [];
        $self->{spot_colour_name} = "a";
        # if we do bullet/image transitions, make sure new pages don't use a transition
        $el->{Attributes}{"{}transition"}{Value} = "replace";
        # $self->{pdf}->set_text_pos(60, 500);
    }
    elsif ($name eq 'title') {
        $self->gathered_text; # reset
        $self->{chars_ok} = 1;
        my $bb = $self->{pdf}->new_bounding_box(
        	x => 5, y => 400, w => 602, h => 50,
            align => "centre",
            );
        $self->{bb} = $bb;
        $bb->set_font(
                    face => $self->{title_font},
                    size => $self->{title_size},
                );
    }
    elsif ($name eq 'i') {
        my $prev = $self->{pdf}->get_parameter("fontname");
        my $new = $prev;
        my $bold = 0;
        if ($new =~ s/-(.*)$//) {
            my $removed = $1;
            if ($removed =~ /Bold/i) {
                $bold = 1;
            }
        }
        push @{$self->{font_stack}}, $prev;
        $self->{bb}->set_font(face => $new, italic => 1, bold => $bold);
    }
    elsif ($name eq 'b') {
        my $prev = $self->{pdf}->get_parameter("fontname");
        my $new = $prev;
        my $italic = 0;
        if ($new =~ s/-(.*)$//) {
            my $removed = $1;
            if ($removed =~ /(Oblique|Italic)/i) {
                $italic = 1;
            }
        }
        push @{$self->{font_stack}}, $prev;
        $self->{bb}->set_font(face => $new, italic => $italic, bold => 1);
    }
    elsif ($name eq 'point') {
        $self->{chars_ok} = 1;
        my $level = $el->{Attributes}{"{}level"}{Value} || 1;
        my ($x, $y) = $self->{pdf}->get_text_pos;

        if (@{$self->{xindent}} && $level <= $self->{xindent}[0]{level}) {
            my $last;
            while ($last = shift @{$self->{xindent}}) {
                if ($last->{level} == $level) {
                    $self->{pdf}->set_text_pos($last->{x}, $y);
                    $x = $last->{x};
                    last;
                }
            }
        }

        if ($level == 1) {
            $self->{pdf}->set_text_pos(80, $y);
        }

        my $size = $self->bullet($level);

        ($x, $y) = $self->{pdf}->get_text_pos;
        my $bb = $self->{pdf}->new_bounding_box(
        	x => $x, y => $y, w => (612 - $x), h => (450 - $y)
        );
        $self->{bb} = $bb;
    }
    elsif ($name eq 'image') {
        my $image = $self->{images}[$self->{image_id}];
        my ($scale, $handle, $href) = @$image;
        image($self->{pdf}, $scale, $handle, $href);
    }
    elsif ($name eq 'source_code' || $name eq 'source-code') {
        my $size = $el->{Attributes}{"{}fontsize"}{Value} || 14;
        $self->{chars_ok} = 1;
		$self->{pdf}->set_font(face => "Courier", size => $size);
        my ($x, $y) = $self->{pdf}->get_text_pos;
        my $bb = $self->{pdf}->new_bounding_box(
        	x => $x, y => $y, w => (612 - $x), h => (450 - $y),
            wrap => 0,
        );
        $self->{bb} = $bb;
    }
    elsif ($name eq 'color' || $name eq 'colour') {
        my $hex_colour;
        if (exists($el->{Attributes}{"{}name"})) {
            my $colour = lc($el->{Attributes}{"{}name"}{Value});
            $hex_colour = $colours{$colour}
                || die "No such colour: $colour";
        }
        else {
            $hex_colour = $el->{Attributes}{"{}rgb"}{Value};
        }
        if (!$hex_colour) {
            die "Missing colour attribute: name or rgb";
        }
        $hex_colour =~ s/^#//;
        if ($hex_colour !~ /^[0-9a-fA-F]{6}$/) {
            die "Invalid hex format: $hex_colour";
        }

        my ($r, $g, $b) = map { hex()/255 } ($hex_colour =~ /(..)/g);

        my $old_colour = $self->{bb}->make_spot_color(
                $self->{spot_colour_name},
            );
        $self->{spot_colour_name}++;
        push @{$self->{spot_colours}}, $old_colour;
        $self->{bb}->set_color(rgb => [$r,$g,$b]);
    }
}

sub slide_end_element {
    my ($self, $el) = @_;

    my $name = $el->{LocalName};

    $el = $self->{SlideCurrent};
    $self->{SlideCurrent} = $el->{Parent};

    if ($name eq 'title' || $name eq 'point' || $name eq 'source-code'
    	|| $name eq 'source_code') {
        # finish bounding box
        $self->{bb}->finish;
        my ($x, $y) = $self->{bb}->get_text_pos;
        $self->{pdf}->set_text_pos($self->{bb}->{x}, $y - 4);
        delete $self->{bb};
        $self->{pdf}->print_line("");
    }

    if ($name eq 'title') {
        # create bookmarks
        if (!$self->{transitional}) {
            my $text = $self->gathered_text;
            $self->push_bookmark(
                $self->{pdf}->add_bookmark(
                    text => $text,
                    level => 3,
                    parent_of => $self->top_bookmark,
                )
            );
        }
        my ($x, $y) = $self->{pdf}->get_text_pos();
        $self->{pdf}->add_link(
            link => $el->{Attributes}{"{}href"}{Value},
            x => 20, y => $y - 5,
            w => 570, h => 24) if exists($el->{Attributes}{"{}href"});

        $self->{pdf}->set_text_pos(60, $y);
        $self->{chars_ok} = 0;
    }
    elsif ($name eq 'slide') {
        $self->pop_bookmark unless $self->{transitional};
    }
    elsif ($name eq 'i' || $name eq 'b') {
        my $font = pop @{$self->{font_stack}};
        $self->{bb}->set_font(face => $font);
    }
    elsif ($name eq 'point') {
        $self->{chars_ok} = 0;
    }
    elsif ($name eq 'source_code' || $name eq 'source-code') {
        $self->{chars_ok} = 0;
    }
    elsif ($name eq 'image') {
        $self->{image_id}++;
    }
    elsif ($name eq 'colour' || $name eq 'color') {
        my $old_colour = pop @{$self->{spot_colours}};
        $self->{bb}->set_colour( spot => { handle => $old_colour, tint => 1 } );
    }
}

sub slide_characters {
    my ($self, $chars) = @_;

    return unless $self->{chars_ok};

    $self->{gathered_text} .= $chars->{Data};

    my $name = $self->{SlideCurrent}->{LocalName};
    my $text = $chars->{Data};
    return unless $text;
    my $leftover = $self->{bb}->print($text);
    if ($leftover) {
    	die "Could not print: $leftover\n";
    }
}

1;
__END__

=head1 NAME

XML::Handler::AxPoint - AxPoint XML to PDF Slideshow generator

=head1 SYNOPSIS

Using SAX::Machines:

  use XML::SAX::Machines qw(Pipeline);
  use XML::Handler::AxPoint;
  
  Pipeline( XML::Handler::AxPoint->new() )->parse_uri("presentation.axp");

Or using directly:

  use XML::SAX;
  use XML::Handler::AxPoint;

  my $parser = XML::SAX::ParserFactory->parser(
  	Handler => XML::Handler::AxPoint->new(
  		Output => "presentation.pdf"
  		)
  	);
  
  $parser->parse_uri("presentation.axp");

=head1 DESCRIPTION

This module is a port and enhancement of the AxKit presentation tool,
B<AxPoint>. It takes an XML description of a slideshow, and generates
a PDF. The resulting presentations are very nice to look at, possibly
rivalling PowerPoint, and almost certainly better than most other
freeware presentation tools on Unix/Linux.

The presentations support slide transitions, PDF bookmarks, bullet
points, source code (fixed font) sections, images, colours, bold and
italics, hyperlinks, and transition effects for all the bullet
points, source, and image sections.

Rather than describing the format in detail, it is far easier to
examine (and copy) the example in the testfiles directory in the
distribution. We have included that verbatim here in case you lost it
during the install:

 <?xml version="1.0"?>
 <slideshow>
 
  <title>AxKit</title>
  <metadata>
     <speaker>Matt Sergeant</speaker>
     <email>matt@axkit.com</email>
     <organisation>AxKit.com Ltd</organisation>
     <link>http://axkit.com/</link>
     <logo scale="0.4">ax_logo.png</logo>
     <background>redbg.png</background>
  </metadata>
  
  <slide transition="dissolve">
    <title>Introduction</title>
    <point level="1">Perl's XML Capabilities</point>
    <point level="1">AxKit intro</point>
    <point level="1">AxKit static sites</point>
    <point level="1">AxKit dynamic sites (XSP)</point>
    <point level="1">Advanced <colour name="red">AxKit</colour></point>
    <source_code>
 Foo!
    </source_code>
  </slide>
  
  <slideset>
     <title>XML with Perl Introduction</title>
     
     <slide>
        <title>
        A very long <i>title that</i> should show how 
        word <i>wrapping in the title</i> tag hopefully works
        properly today
        </title>
        <point level="1">SAX-like API</point>
        <point level="1">register callback handler methods</point>
        <point level="2">start tag</point>
        <point level="2">end tag</point>
        <point level="2">characters</point>
        <point level="2">comments</point>
        <point level="2">processing instructions</point>
        <source_code>
 &lt;?pi here?>
        </source_code>
        <point level="2">... and more</point>
        <point level="1">Non validating XML parser</point>
        <point level="1">dies (throws an exception) on bad XML</point>
     </slide>
     
     <slide>
        <title>XML::Parser code</title>
        <source_code>
 my $p = XML::Parser->new(
 <i>    Handlers => { # should be in italics!
        Start => \&amp;start_tag, 
        End => \&amp;end_tag,
        # add more handlers here
        });
    </i>
 $p->parsefile("foo.xml");
 
 exit(0);
 
 sub start_tag {
  my ($expat, $tag, %attribs) = @_;
  print "Start tag: $tag\n";
 }
 
 sub end_tag {
  my ($expat, $tag) = @_;
  print "End tag: $tag\n";
 }
        </source_code>
     </slide>
     
     <slide>
     <title>XML::XPath Implementation</title>
     <point level="1">XML::Parser and SAX parsers build an in-memory tree</point>
     <point level="1">Hand-built parser for XPath syntax (rather than YACC based parser)</point>
     <point level="1">Garbage Collection yet still has circular references (and works on Perl 5.005)</point>
     <image>pointers.png</image>
     </slide>
     
  </slideset>
  
  <slide>
  <title>Conclusions</title>
  <point level="1" transition="dissolve">Perl and XML are a powerful combination</point>
  <point level="1" transition="replace">XPath and XSLT add to the mix...</point>
  <point level="1" transition="glitter">AxKit can reduce your long term costs</point>
  <point level="2" transition="dissolve">In site re-design</point>
  <point level="2" transition="box">and in content re-purposing</point>
  <point level="1" transition="wipe">Open Source equal to commercial alternatives</point>
  <image transition="dissolve">world_map-960.png</image>
  </slide>
  
  <slide>
  <title>Resources and contact</title>
  <point level="1">AxKit: http://axkit.org/</point>
  <point level="1">CPAN: http://search.cpan.org</point>
  <point level="1">libxml and libxslt: http://www.xmlsoft.org</point>
  <point level="1">Sablotron: http://www.gingerall.com</point>
  <point level="1">XPath and XSLT Tutorials: http://zvon.org</point>
  </slide>
  
 </slideshow>

=cut
