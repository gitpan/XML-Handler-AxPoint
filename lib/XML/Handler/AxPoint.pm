# $Id: AxPoint.pm,v 1.33 2002/06/11 07:39:24 matt Exp $

package XML::Handler::AxPoint;
use strict;

use XML::SAX::Writer;
use File::Spec;
use File::Basename;
use PDFLib 0.11;

use vars qw($VERSION);
$VERSION = '1.30';

sub new {
    my $class = shift;
    my $opt   = (@_ == 1)  ? { %{shift()} } : {@_};

    $opt->{Output} ||= *{STDOUT}{IO};
    $opt->{gathered_text} = '';

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

    $self->{normal_font} = "Helvetica";

    $self->{todo} = [];
    $self->{bookmarks} = [];

    $self->{default_transition} = [];
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
    $transition = 'replace' if $transition eq 'none';
    $transition = 'replace' if $self->{PrintMode};

    $self->{pdf}->set_parameter(transition => lc($transition));

    if (my $bg = $self->{bg}) {
        $self->{pdf}->add_image(img => $bg->{image}, x => 0, y => 0, scale => $bg->{scale});
    }

    if (my $logo = $self->{logo}) {
        my $logo_w = $logo->{image}->width * $logo->{scale};
        $self->{pdf}->add_image(img => $logo->{image}, x => 612 - $logo_w - $logo->{x}, y => $logo->{y}, scale => $logo->{scale});
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

    # warn("start_ $name\n");

    if ($name eq 'slideshow') {
        $self->push_todo(sub { $self->new_page });
        if (exists($el->{Attributes}{"{}default-transition"})) {
            unshift @{$self->{default_transition}}, $el->{Attributes}{"{}default-transition"}{Value};
        }
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
        if (exists($el->{Attributes}{"{}x"})) {
            $self->{logo}{x} = $el->{Attributes}{"{}x"}{Value};
        }
        if (exists($el->{Attributes}{"{}y"})) {
            $self->{logo}{y} = $el->{Attributes}{"{}y"}{Value};
        }
    $self->{logo}{x} ||= 0;
    $self->{logo}{y} ||= 0;
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
        if (exists($el->{Attributes}{"{}default-transition"})) {
            unshift @{$self->{default_transition}}, $el->{Attributes}{"{}default-transition"}{Value};
        }
        $self->new_page;
    }
    elsif ($name eq 'subtitle') {
    }
    elsif ($name eq 'slide') {
        $self->run_todo; # might need to create slideset here.
        $self->{pdf}->end_page;

        if (exists($el->{Attributes}{"{}default-transition"})) {
            unshift @{$self->{default_transition}}, $el->{Attributes}{"{}default-transition"}{Value};
        }
        $self->{images} = [];
        # cache these events now...
        $self->{cache_until} = $el->{Name};
        $self->{cache} = [["slide_start_element", $el]];
    }
    elsif ($name eq 'image') {
        $self->gathered_text;
        if (exists($el->{Attributes}{"{http://www.w3.org/1999/xlink}href"})) {
            # uses xlink, not characters
            $self->characters({ Data => $el->{Attributes}{"{http://www.w3.org/1999/xlink}href"}{Value}});
        }
    }
    elsif ($name =~ /(point|source[_-]code|i|b|colou?r|table|row|col|rect|circle|ellipse|polyline|line|path|text|span)/) {
      # passthrough to allow these types
    }
    else {
        warn("Unknown tag: $name");
    }
}

sub end_element {
    my ($self, $el) = @_;

    if ($self->{cache_until}) {
        push @{$self->{cache}}, ["slide_end_element", $el];
        if ($el->{Name} eq $self->{cache_until}) {
            delete $self->{cache_until};
            $self->playback_cache;
        }
    }

    $el = $self->{Current};
    my $parent = $self->{Current} = $el->{Parent};

    my $name = $el->{LocalName};
    # warn("end_ $name\n");
    if ($name eq 'slideshow') {
        $self->run_todo;
        if (exists($el->{Attributes}{"{}default-transition"})) {
            shift @{$self->{default_transition}};
        }
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
        my $logo_file =
            File::Spec->rel2abs(
                $self->gathered_text,
                File::Basename::dirname($self->{locator}{SystemId} || '')
            );
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
        my $bg_file =
            File::Spec->rel2abs(
                $self->gathered_text,
                File::Basename::dirname($self->{locator}{SystemId} || '')
            );
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
        if (exists($el->{Attributes}{"{}default-transition"})) {
            shift @{$self->{default_transition}};
        }
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
        if (exists($el->{Attributes}{"{}default-transition"})) {
            shift @{$self->{default_transition}};
        }
    }
    elsif ($name eq 'image') {
        my $image =
            File::Spec->rel2abs(
                $self->gathered_text,
                File::Basename::dirname($self->{locator}{SystemId} || '')
            );
        my $image_ref = $self->{pdf}->load_image(
                filename => $image,
                filetype => get_filetype($image),
            );
        my $scale = $el->{Attributes}{"{}scale"}{Value} || 1.0;
        my $href = $el->{Attributes}{"{}href"}{Value};
        my $x = $el->{Attributes}{"{}x"}{Value};
        my $y = $el->{Attributes}{"{}y"}{Value};
        my $width = $el->{Attributes}{"{}width"}{Value};
        my $height = $el->{Attributes}{"{}height"}{Value};

        push @{$self->{images}},
            {
                scale => $scale,
                image_ref => $image_ref,
                href => $href,
                x => $x,
                y => $y,
                width => $width,
                height => $height,
            };
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
    my ($self, $scale, $file_handle, $href) = @_;
    my $pdf = $self->{pdf};

    $pdf->print_line("");

    my ($x, $y) = $pdf->get_text_pos;

    my ($imgw, $imgh) = (
            $pdf->get_value("imagewidth", $file_handle->img),
            $pdf->get_value("imageheight", $file_handle->img)
            );

    $imgw *= $scale;
    $imgh *= $scale;

    my $xpos = (($self->{extents}[0]{x} + ($self->{extents}[0]{w} / 2))
                    - ($imgw / 2));
    my $ypos = ($y - $imgh);

    $pdf->add_image(img => $file_handle,
            x => $xpos,
            y => $ypos,
            scale => $scale);
    $pdf->add_link(link => $href, x => $xpos, y => $ypos, w => $imgw, h => $imgh) if $href;

    $pdf->set_text_pos($x, $ypos);
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
    $pdf->set_font(face => $self->{normal_font}, size => $size);
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

sub get_colour {
    my $colour = shift;
    if ($colour !~ s/^#//) {
        $colour = $colours{$colour} || die "Unknown colour: $colour";
    }
    if ($colour !~ /^[0-9a-fA-F]{6}$/) {
        die "Invalid colour format: #$colour";
    }
    my ($r, $g, $b) = map { hex()/255 } ($colour =~ /(..)/g);
    return [$r, $g, $b];
}

sub process_css_styles {
    my ($self, $style, $text_mode) = @_;

    if ($text_mode) {
        $self->{stroke} = 0;
        $self->{fill} = 1;
    }
    else {
        $self->{stroke} = 1;
        $self->{fill} = 0;
    }

    return unless $style;

    my $pdf = $self->{bb} || $self->{pdf};

    my $prev_font = $pdf->get_parameter("fontname");
    my $new_font = $prev_font;
    my $bold = 0;
    my $italic = 0;
    my $size = $pdf->get_value('fontsize');
    if ($new_font =~ s/-(.*)$//) {
        my $removed = $1;
        if ($removed =~ /Bold/i) {
            $bold = 1;
        }
        if ($removed =~ /(Oblique|Italic)/i) {
            $italic = 1;
        }
    }
    foreach my $part (split(/;\s*/s, $style)) {
        my ($key, $value) = split(/\s*:\s*/, $part, 2);
        # Keys we need to implement:
        # color, fill, font, font-style, font-weight, font-size,
        # font-family, stroke, stroke-linecap, stroke-linejoin, stroke-width,

        # warn("got $key = $value\n");
        if ($key eq 'font') {
            # [ [ <'font-style'> || <'font-variant'> || <'font-weight'> ]? <'font-size'> [ / <'line-height'> ]? <'font-family'> ]
            if ($value =~ /^((\S+)\s+)?((\S+)\s+)(\S+)$/) {
                my ($attribs, $ptsize, $name) = ($2, $4, $5);
                $attribs ||= 'inherit';
                if ($attribs eq 'normal') {
                    $bold = 0; $italic = 0;
                }
                elsif ($attribs eq 'inherit') {
                    # Do nothing
                }
                elsif ($attribs eq 'bold' || $attribs eq 'bolder') {
                    $bold = 1;
                }
                elsif ($attribs eq 'italic' || $attribs eq 'oblique') {
                    $italic = 1;
                }

                if ($ptsize !~ s/pt$//) {
                    die "Cannot support fonts in anything but point sizes yet: $value";
                }
                $size = $ptsize;

                $name =~ s/sans-serif/Helvetica/;
                $name =~ s/serif/Times/;
                $name =~ s/monospace/Courier/;
                $new_font = $name;
            }
            else {
                die "Failed to parse CSS font attribute: $value";
            }
        }
        elsif ($key eq 'font-family') {
            $value =~ s/sans-serif/Helvetica/;
            $value =~ s/serif/Times/;
            $value =~ s/monospace/Courier/;
            $new_font = $value;
        }
        elsif ($key eq 'font-style') {
            if ($value eq 'normal') {
                $italic = 0;
            }
            elsif ($value eq 'italic') {
                $italic = 1;
            }
        }
        elsif ($key eq 'font-weight') {
            if ($value eq 'normal') {
                $bold = 0;
            }
            elsif ($value eq 'bold') {
                $bold = 1;
            }
        }
        elsif ($key eq 'font-size') {
            if ($value !~ s/pt$//) {
                die "Can't do anything but font-size in pt yet";
            }
            $size = $value;
        }
        elsif ($key eq 'color') {
            # set both the stroke and fill color
            $pdf->set_colour(rgb => get_colour($value), type => "both");
        }
        elsif ($key eq 'fill') {
            if ($value eq 'none') {
                $self->{fill} = 0;
            }
            else {
                # it's a color
                $self->{fill} = 1;
                $pdf->set_colour(rgb => get_colour($value), type => "fill");
            }
        }
        elsif ($key eq 'fill-rule') {
            $value = 'winding' if $value eq 'nonzero';
            $pdf->set_parameter(fillrule => $value);
        }
        elsif ($key eq 'stroke') {
            if ($value eq 'none') {
                $self->{stroke} = 0;
            }
            else {
                # it's a color
                $self->{stroke} = 1;
                $pdf->set_colour(rgb => get_colour($value), type => "stroke");
            }
        }
        elsif ($key eq 'stroke-linecap') {
            $pdf->set_line_cap("${value}_end"); # PDFLib takes care of butt|round|square
        }
        elsif ($key eq 'stroke-linejoin') {
            $pdf->set_line_join($value); # PDFLib takes care of miter|round|bevel
        }
        elsif ($key eq 'stroke-width') {
            $pdf->set_line_width($value);
        }
        elsif ($key eq 'stroke-miterlimit') {
            $pdf->set_miter_limit($value);
        }
    }

    return unless $text_mode;

    push @{$self->{font_stack}}, $prev_font;

    my $ok = 0;
#    warn(sprintf("set_font(%s => %s, %s => %s, %s => %s, %s => %s)\n",
#                    face => $new_font,
#                    italic => $italic,
#                    bold => $bold,
#                    size => $size,
#                    )
#    );
    foreach my $face (split(/\s*/, $new_font)) {
        eval {
            $pdf->set_font(
                    face => $new_font,
                    italic => $italic,
                    bold => $bold,
                    size => $size,
                    );
        };
        if (!$@) {
            $ok = 1;
            last;
        }
    }
    if (!$ok) {
        die "Unable to find font: $new_font : $@";
    }
}

sub slide_start_element {
    my ($self, $el) = @_;

    $self->{SlideCurrent} = $el;

    my $name = $el->{LocalName};

    # warn("slide_start_ $name\n");

    # transitions...
    if ( (!$self->{PrintMode}) &&
        $name =~ /^(point|image|source[_-]code|table|col|row|circle|ellipse|rect|text|line|path)$/) {
        if (exists($el->{Attributes}{"{}transition"})
            || @{$self->{default_transition}}) {
            # has a transition
            my $trans = $el->{Attributes}{"{}transition"};
            # default transition if unspecified (and not for table tags)
            if ( (!$trans) && ($name ne 'table') && ($name ne 'row') && ($name ne 'col') ) {
                $trans = { Value => $self->{default_transition}[0] };
            }
            if ($trans && ($trans->{Value} ne 'none') ) {
                my @cache = @{$self->{cache_trash}};
                local $self->{cache} = \@cache;
                local $self->{cache_trash};
                # warn("playback on $el\n");
                $self->{transitional} = 1;
                my $parent = $el->{Parent};
                while ($parent) {
                    last if $parent->{LocalName} eq 'slide';
                    $parent = $parent->{Parent};
                }
                die "No parent slide element" unless $parent;
                local $parent->{Attributes}{"{}transition"}{Value} = $trans->{Value};
                $self->playback_cache; # should get us back here.
                $self->run_todo;
                # make sure we don't transition this node again
                $el->{Attributes}{"{}transition"}{Value} = 'none';
                # warn("playback returns\n");
                $self->{transitional} = 0;
            }
        }
    }

    if ($name eq 'slide') {
        $self->new_page;
        $self->{image_id} = 0;
        $self->{colour_stack} = [[0,0,0]];
        # if we do bullet/image transitions, make sure new pages don't use a transition
        $el->{Attributes}{"{}transition"}{Value} = "replace";
        $self->{extents} = [{ x => 0, w => 612 }];
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
    elsif ($name eq 'table') {
        # push extents.
        $self->{extents} = [{ %{$self->{extents}[0]} }, @{$self->{extents}}];
        $self->{col_widths} = [];
        my ($x, $y) = $self->{pdf}->get_text_pos;
        $self->{pdf}->set_text_pos($self->{extents}[1]{x}, $y);
        $self->{max_height} = $y;
        $self->{row_number} = 0;
    }
    elsif ($name eq 'row') {
        $self->{col_number} = 0;
        $self->{row_start} = [];
        @{$self->{row_start}} = $self->{pdf}->get_text_pos;
    }
    elsif ($name eq 'col') {
        my $width;
        my $prev_x = $self->{extents}[1]{x};
        if ($self->{row_number} > 0) {
            $width = $self->{col_widths}[$self->{col_number}];
        }
        else {
            $width = $el->{Attributes}{"{}width"}{Value};
            $width =~ s/%$// || die "Column widths must be in percentages";
            # warn("calculating ${width}% of $self->{extents}[1]{w}\n");
            $width = $self->{extents}[1]{w} * ($width/100);
            $self->{col_widths}[$self->{col_number}] = $width;
        }
        if ($self->{col_number} > 0) {
            my $up_to = $self->{col_number} - 1;
            foreach my $col (0 .. $up_to) {
                $prev_x += $self->{col_widths}[$col];
            }
        }
        # warn("col setting extents to x => $prev_x, w => $width\n");
        $self->{extents}[0]{x} = $prev_x;
        $self->{extents}[0]{w} = $width;
        $self->{pdf}->set_text_pos(@{$self->{row_start}});
    }
    elsif ($name eq 'i') {
        my $prev = $self->{pdf}->get_parameter("fontname") || $self->{normal_font};
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
            my $indent = 80 * ($self->{extents}[0]{w} / $self->{extents}[-1]{w});
            $self->{pdf}->set_text_pos($self->{extents}[0]{x} + $indent, $y);
        }

        my $size = $self->bullet($level);

        ($x, $y) = $self->{pdf}->get_text_pos;
        # warn(sprintf("creating new bb: %s => %d, %s => %d, %s => %d, %s => %d",
        #     x => $x, y => $y, w => ($self->{extents}[0]{w} - ($x - $self->{extents}[0]{x})), h => (450 - $y)
        #     ));
        my $bb = $self->{pdf}->new_bounding_box(
            x => $x, y => $y, w => ($self->{extents}[0]{w} - ($x - $self->{extents}[0]{x})), h => (450 - $y)
        );
        $self->{bb} = $bb;
    }
    elsif ($name eq 'image') {
        my $image = $self->{images}[$self->{image_id}];
        my ($scale, $handle, $href) =
            ($image->{scale}, $image->{image_ref}, $image->{href});
        if (defined($image->{x}) && defined($image->{y})) {
            my $pdf = $self->{pdf};
            # TODO - use coords scaling to support width/height
            $pdf->add_image(img => $handle,
                x => $image->{x},
                y => $image->{y},
                scale => $scale
            );
        }
        else {
            $self->image($scale, $handle, $href);
        }
    }
    elsif ($name eq 'source_code' || $name eq 'source-code') {
        my $size = $el->{Attributes}{"{}fontsize"}{Value} || 14;
        $self->{chars_ok} = 1;

        my ($x, $y) = $self->{pdf}->get_text_pos;
        my $indent = 80 * ($self->{extents}[0]{w} / $self->{extents}[-1]{w});
        $self->{pdf}->set_text_pos($self->{extents}[0]{x} + $indent, $y);

        $self->{pdf}->set_font(face => "Courier", size => $size);
        ($x, $y) = $self->{pdf}->get_text_pos;
        my $bb = $self->{pdf}->new_bounding_box(
            x => $x, y => $y, w => ($self->{extents}[0]{w} - ($x - $self->{extents}[0]{x})), h => (450 - $y),
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
            die "Missing colour attribute: name or rgb (found: " . join(', ', keys(%{$el->{Attributes}})) .")";
        }
        $hex_colour =~ s/^#//;
        if ($hex_colour !~ /^[0-9a-fA-F]{6}$/) {
            die "Invalid hex format: $hex_colour";
        }

        my ($r, $g, $b) = map { hex()/255 } ($hex_colour =~ /(..)/g);

        push @{$self->{colour_stack}}, [$r,$g,$b];
        $self->{bb}->set_color(rgb => [$r,$g,$b]);
    }
    elsif ($name eq 'span') {
        my $prev = $self->{pdf}->get_parameter("fontname");
        push @{$self->{font_stack}}, $prev;
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value}, 1);
    }
    elsif ($name eq 'rect') {
        my ($x, $y, $width, $height) = (
            $el->{Attributes}{"{}x"}{Value},
            $el->{Attributes}{"{}y"}{Value},
            $el->{Attributes}{"{}width"}{Value},
            $el->{Attributes}{"{}height"}{Value},
            );
        $self->{pdf}->save_graphics_state();
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value});
        $self->{pdf}->rect(x => $x, y => $y, w => $width, h => $height);
        if ($self->{fill} && $self->{stroke}) {
            $self->{pdf}->fill_stroke;
        }
        elsif ($self->{fill}) {
            $self->{pdf}->fill;
        }
        elsif ($self->{stroke}) {
            $self->{pdf}->stroke;
        }
    }
    elsif ($name eq 'circle') {
        my ($cx, $cy, $r) = (
            $el->{Attributes}{"{}cx"}{Value},
            $el->{Attributes}{"{}cy"}{Value},
            $el->{Attributes}{"{}r"}{Value},
            );
        $self->{pdf}->save_graphics_state();
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value});
        $self->{pdf}->circle(x => $cx, y => $cy, r => $r);
        if ($self->{fill} && $self->{stroke}) {
            $self->{pdf}->fill_stroke;
        }
        elsif ($self->{fill}) {
            $self->{pdf}->fill;
        }
        elsif ($self->{stroke}) {
            $self->{pdf}->stroke;
        }
    }
    elsif ($name eq 'ellipse') {
        my ($cx, $cy, $rx, $ry) = (
            $el->{Attributes}{"{}cx"}{Value},
            $el->{Attributes}{"{}cy"}{Value},
            $el->{Attributes}{"{}rx"}{Value},
            $el->{Attributes}{"{}ry"}{Value},
            );
        my $r = $rx;
        my $scale = $ry / $r;
        $cy /= $scale;
        # warn("ellipse at $cx, $cy, scale: $scale, r: $r\n");
        $self->{pdf}->save_graphics_state();
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value});
        $self->{pdf}->coord_scale(1, $scale);
        $self->{pdf}->circle(x => $cx, y => $cy, r => $r);
        if ($self->{fill} && $self->{stroke}) {
            $self->{pdf}->fill_stroke;
        }
        elsif ($self->{fill}) {
            $self->{pdf}->fill;
        }
        elsif ($self->{stroke}) {
            $self->{pdf}->stroke;
        }
    }
    elsif ($name eq 'line') {
        my ($x1, $y1, $x2, $y2) = (
            $el->{Attributes}{"{}x1"}{Value},
            $el->{Attributes}{"{}y1"}{Value},
            $el->{Attributes}{"{}x2"}{Value},
            $el->{Attributes}{"{}y2"}{Value},
            );
        $self->{pdf}->save_graphics_state();
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value});
        $self->{pdf}->move_to($x1, $y1);
        $self->{pdf}->line_to($x2, $y2);
        if ($self->{fill} && $self->{stroke}) {
            $self->{pdf}->fill_stroke;
        }
        elsif ($self->{fill}) {
            $self->{pdf}->fill;
        }
        elsif ($self->{stroke}) {
            $self->{pdf}->stroke;
        }
    }
    elsif ($name eq 'text') {
        my ($x, $y) = (
            $el->{Attributes}{"{}x"}{Value},
            $el->{Attributes}{"{}y"}{Value},
        );
        $self->{pdf}->save_graphics_state();
        $self->{pdf}->set_font( face => $self->{normal_font}, size => 14.0 );
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value}, 1);
        $self->{pdf}->set_text_pos($x, $y);
        $self->{chars_ok} = 1;
        $self->gathered_text; # reset
        if ($self->{fill} && $self->{stroke}) {
            $self->{pdf}->set_value(textrendering => 2);
        }
        elsif ($self->{fill}) {
            $self->{pdf}->set_value(textrendering => 0);
        }
        elsif ($self->{stroke}) {
            $self->{pdf}->set_value(textrendering => 1);
        }
        else {
            $self->{pdf}->set_value(textrendering => 3); # invisible
        }
    }
    elsif ($name eq 'path') {
        my ($data) = (
            $el->{Attributes}{"{}d"}{Value},
            );
        $self->{pdf}->save_graphics_state();
        $self->process_css_styles($el->{Attributes}{"{}style"}{Value});
        $self->process_path($data);
    }
}

sub acos {
    return atan2( sqrt(1 - $_[0]**2), $_[0] );
}

use constant PI => atan2(1, 1) * 4.0;

sub convert_from_svg
{
    my ($x0, $y0, $rx, $ry, $phi, $large_arc, $sweep, $x, $y) = @_;
    my ($cx, $cy, $theta, $delta);
    
    # a plethora of temporary variables 
    my (
        $dx2, $dy2, $phi_r, $x1, $y1,
        $rx_sq, $ry_sq,
        $x1_sq, $y1_sq,
        $sign, $sq, $coef,
        $cx1, $cy1, $sx2, $sy2,
        $p, $n,
        $ux, $uy, $vx, $vy
    );
        
    # Compute 1/2 distance between current and final point
    $dx2 = ($x0 - $x) / 2.0;
    $dy2 = ($y0 - $y) / 2.0;

    # Convert from degrees to radians
    my $pi = atan2(1, 1) * 4.0;
    $phi %= 360;
    $phi_r = $phi * $pi / 180.0;

    # Compute (x1, y1)
    $x1 = cos($phi_r) * $dx2 + sin($phi_r) * $dy2;
    $y1 = -sin($phi_r) * $dx2 + cos($phi_r) * $dy2;

    # Make sure radii are large enough
    $rx = abs($rx); $ry = abs($ry);
    $rx_sq = $rx * $rx;
    $ry_sq = $ry * $ry;
    $x1_sq = $x1 * $x1;
    $y1_sq = $y1 * $y1;

    my $radius_check = ($x1_sq / $rx_sq) + ($y1_sq / $ry_sq);
    if ($radius_check > 1)
    {
        $rx *= sqrt($radius_check);
        $ry *= sqrt($radius_check);
        $rx_sq = $rx * $rx;
        $ry_sq = $ry * $ry;
    }

    # Step 2: Compute (cx1, cy1)

    $sign = ($large_arc == $sweep) ? -1 : 1;
    $sq = (($rx_sq * $ry_sq) - ($rx_sq * $y1_sq) - ($ry_sq * $x1_sq)) /
        (($rx_sq * $y1_sq) + ($ry_sq * $x1_sq));
    $sq = ($sq < 0) ? 0 : $sq;
    $coef = ($sign * sqrt($sq));
    $cx1 = $coef * (($rx * $y1) / $ry);
    $cy1 = $coef * -(($ry * $x1) / $rx);

    #   Step 3: Compute (cx, cy) from (cx1, cy1)

    $sx2 = ($x0 + $x) / 2.0;
    $sy2 = ($y0 + $y) / 2.0;

    $cx = $sx2 + (cos($phi_r) * $cx1 - sin($phi_r) * $cy1);
    $cy = $sy2 + (sin($phi_r) * $cx1 + cos($phi_r) * $cy1);

    #   Step 4: Compute angle start and angle extent

    $ux = ($x1 - $cx1) / $rx;
    $uy = ($y1 - $cy1) / $ry;
    $vx = (-$x1 - $cx1) / $rx;
    $vy = (-$y1 - $cy1) / $ry;
    $n = sqrt( ($ux * $ux) + ($uy * $uy) );
    $p = $ux; # 1 * ux + 0 * uy
    $sign = ($uy < 0) ? -1 : 1;

    $theta = $sign * acos( $p / $n );
    $theta = $theta * 180 / $pi;

    $n = sqrt(($ux * $ux + $uy * $uy) * ($vx * $vx + $vy * $vy));
    $p = $ux * $vx + $uy * $vy;
    $sign = (($ux * $vy - $uy * $vx) < 0) ? -1 : 1;
    $delta = $sign * acos( $p / $n );
    $delta = $delta * 180 / $pi;

    if ($sweep == 0 && $delta > 0)
    {
        $delta -= 360;
    }
    elsif ($sweep == 1 && $delta < 0)
    {
        $delta += 360;
    }

    #$delta -= 360 if $delta >= 360;
    #$theta -= 360 if $theta >= 360;
    # delta %= 360;
    $theta %= 360;
    
    return ($cx, $cy, $rx, $ry, $theta, $delta, $phi);
}

sub process_path {
    my $self = shift;
    my ($data) = @_;
    $data =~ s/^\s*//;
    my @parts = split(/([A-Za-z])/, $data);
    # warn("got: '", join("', '", @parts), "'\n");
    shift(@parts); # get rid of junk at start
    
    my $relative = 0;

    my ($xoffset, $yoffset) = map { $self->{pdf}->get_value($_) } qw(currentx currenty);

    my ($last_reflect_x, $last_reflect_y, $need_to_close);

    while (@parts) {
        my $type = shift(@parts);
        my $rest = shift(@parts);

        if ($type eq lc($type)) {
            # warn("using relative coordinates\n");
            $relative++;
        }

        my @coords = grep { /^[\d\.\-]+$/ } split(/[^\d\.\-]+/, $rest||'');
        # warn("got coords: '", join("', '", @coords), "'\n");

        my ($x, $y);

        if (lc($type) eq 'm') { # moveto
            if (@coords % 2) {
                warn("moveto coords must be in pairs, skipping.\n");
                next;
            }
            
            $need_to_close = 1;

            ($x, $y) = splice(@coords, 0, 2);
            if ($relative) {
                $x += $xoffset;
                $y += $yoffset;
            }
            # warn("move_to($x, $y)\n");
            $self->{pdf}->move_to($x, $y);

            if (@coords) {
                # more coords == lines
                unshift @parts, ($relative ? 'l' : 'L'), join(',', @coords);
                next;
            }
            $xoffset = $x; $yoffset = $y;
        }
        elsif (lc($type) eq 'z') { # closepath
            if ($self->{fill} && $self->{stroke}) {
                $self->{pdf}->close_path_fill_stroke;
            }
            elsif ($self->{fill}) {
                $self->{pdf}->close_path_fill;
            }
            elsif ($self->{stroke}) {
                $self->{pdf}->close_path_stroke;
            }
        }
        elsif (lc($type) eq 'l') { # lineto
            if (@coords % 2) {
                warn("moveto coords must be in pairs, skipping.\n");
                next;
            }

            $need_to_close = 1;

            while(@coords) {
                ($x, $y) = splice(@coords, 0, 2);
                # warn("line: $x, $y\n");
                if ($relative) {
                    $x += $xoffset;
                    $y += $yoffset;
                }
                # warn("line_to($x, $y)\n");
                $self->{pdf}->line_to($x, $y);
            }
            $xoffset = $x; $yoffset = $y;
        }
        elsif (lc($type) eq 'h') { # horizontal lineto
            $need_to_close = 1;

            while (@coords) {
                $x = shift @coords;
                if ($relative) {
                    $x += $xoffset;
                }
                $self->{pdf}->line_to($x, $yoffset);
            }
            $xoffset = $x;
        }
        elsif (lc($type) eq 'v') { # vertical lineto
            $need_to_close = 1;

            while (@coords) {
                $y = shift @coords;
                if ($relative) {
                    $y += $yoffset;
                }
                $self->{pdf}->line_to($xoffset, $y);
            }
            $yoffset = $y;
        }
        elsif (lc($type) eq 'c') { # curveto
            if (@coords % 6) {
                warn("curveto coords must be in 6's, skipping.\n");
                next;
            }
            
            $need_to_close = 1;

            while (@coords) {
                my ($x1, $y1, $x2, $y2, $x3, $y3) = splice(@coords, 0, 6);
                if ($relative) {
                    for ($x1, $x2, $x3) {
                        $_ += $xoffset;
                    }
                    for ($y1, $y2, $y3) {
                        $_ += $yoffset;
                    }
                }
                $self->{pdf}->bezier(
                    x1 => $x1, y1 => $y1,
                    x2 => $x2, y2 => $y2,
                    x3 => $x3, y3 => $y3,
                    );
                ($last_reflect_x, $last_reflect_y) = ($x2, $y2);
                ($x, $y) = ($x3, $y3);
            }
            $xoffset = $x; $yoffset = $y;
        }
        elsif (lc($type) eq 's') { # shorthand/smooth curveto
            if (@coords % 4) {
                warn("shorthand curveto coords must be in 4's, skipping.\n");
                next;
            }
            
            $need_to_close = 1;

            while (@coords) {
                my ($x2, $y2, $x3, $y3) = splice(@coords, 0, 4);
                if ($relative) {
                    $x2 += $xoffset;
                    $x3 += $xoffset;
                    $y2 += $yoffset;
                    $y3 += $yoffset;
                }
                my ($x1, $y1);
                if (defined($last_reflect_x)) {
                    $x1 = $xoffset - ($last_reflect_x - $xoffset);
                    $y1 = $yoffset - ($last_reflect_y - $yoffset);
                }
                else {
                    $x1 = $xoffset;
                    $y1 = $yoffset;
                }
                $self->{pdf}->bezier(
                    x1 => $x1, y1 => $y1,
                    x2 => $x2, y2 => $y2,
                    x3 => $x3, y3 => $y3,
                    );
                ($last_reflect_x, $last_reflect_y) = ($x2, $y2);
                ($x, $y) = ($x3, $y3);
            }
            $xoffset = $x; $yoffset = $y;
        }
        elsif (lc($type) eq 'q') { # quadratic bezier curveto
            if (@coords % 4) {
                warn("quadratic curveto coords must be in 4's, skipping.\n");
                next;
            }
            
            $need_to_close = 1;

            while (@coords) {
                my ($x1, $y1, $x3, $y3) = splice(@coords, 0, 4);
                if ($relative) {
                    for ($x1, $x3) {
                        $_ += $xoffset;
                    }
                    for ($y1, $y3) {
                        $_ += $yoffset;
                    }
                }
                my ($x2, $y2) = ($x1, $y1);
                $self->{pdf}->bezier(
                    x1 => $x1, y1 => $y1,
                    x2 => $x2, y2 => $y2,
                    x3 => $x3, y3 => $y3,
                    );
                ($last_reflect_x, $last_reflect_y) = ($x2, $y2);
                ($x, $y) = ($x3, $y3);
            }
            $xoffset = $x; $yoffset = $y;
        }
        elsif (lc($type) eq 't') { # shorthand/smooth quadratic bezier curveto
            if (@coords % 2) {
                warn("shorthand quadratic curveto coords must be in pairs, skipping.\n");
                next;
            }
            
            $need_to_close = 1;

            while (@coords) {
                my ($x3, $y3) = splice(@coords, 0, 2);
                if ($relative) {
                    $x3 += $xoffset;
                    $y3 += $yoffset;
                }
                my ($x1, $y1, $x2, $y2);
                if (defined($last_reflect_x)) {
                    $x1 = $xoffset - ($last_reflect_x - $xoffset);
                    $y1 = $yoffset - ($last_reflect_y - $yoffset);
                }
                else {
                    $x1 = $xoffset;
                    $y1 = $yoffset;
                }
                ($x2, $y2) = ($x1, $y1);
                $self->{pdf}->bezier(
                    x1 => $x1, y1 => $y1,
                    x2 => $x2, y2 => $y2,
                    x3 => $x3, y3 => $y3,
                    );
                ($last_reflect_x, $last_reflect_y) = ($x2, $y2);
                ($x, $y) = ($x3, $y3);
            }
            $xoffset = $x; $yoffset = $y;
        }
        elsif (lc($type) eq 'a') { # elliptical arc
            if (@coords % 7) {
                warn("elliptical arc coords must be in 7's, skipping.\n");
                next;
            }
            
            while (@coords) {
                my ($rx, $ry, $rot, $large_arc_flag, $sweep_flag, $x2, $y2) =
                    splice(@coords, 0, 7);

                if ($relative) {
                    $x2 += $xoffset;
                    $y2 += $yoffset;
                }

                # warn("arc($xoffset,$yoffset $rest)\n");

                my ($cx, $cy, $_rx, $_ry, $theta, $delta, $phi) =
                    convert_from_svg(
                                $xoffset, $yoffset, 
                                $rx, $ry, 
                                $rot, $large_arc_flag, $sweep_flag, 
                                $x2, $y2);
                
                $delta = sprintf("%0.3f", $delta);
                my $clockwise = abs($delta) < 180;
                # warn("Theta: $theta\n", "Delta: $delta\n");
                my $end_angle = $theta + $delta;

                $end_angle %= 360;

                # warn("actually doing arc: $cx,$cy $_rx,$_ry, $theta,$end_angle, $phi (cw: $clockwise)\n");

                my $r = $_rx;
                my $scale = $_ry / $r;
                $cy /= $scale;

                if ($need_to_close) {
                    $self->{pdf}->line_to($xoffset, $yoffset);
                    if ($self->{fill} && $self->{stroke}) {
                        $self->{pdf}->fill_stroke;
                    }
                    elsif ($self->{fill}) {
                        $self->{pdf}->fill;
                    }
                    elsif ($self->{stroke}) {
                        $self->{pdf}->stroke;
                    }
                    $need_to_close = 0;
                }

                $self->{pdf}->save_graphics_state();
                $self->{pdf}->coord_scale(1, $scale);
                $self->{pdf}->coord_translate($cx, $cy);
                # warn("rotating coords by $phi");
                $self->{pdf}->coord_rotate($phi);

                $self->{pdf}->arc(
                    x => 0, y => 0,
                    r => $r,
                    alpha => $theta,
                    beta => $end_angle,
                    clockwise => $clockwise,
                );

                if ($self->{fill} && $self->{stroke}) {
                    $self->{pdf}->fill_stroke;
                }
                elsif ($self->{fill}) {
                    $self->{pdf}->fill;
                }
                elsif ($self->{stroke}) {
                    $self->{pdf}->stroke;
                }

                $self->{pdf}->restore_graphics_state();
                ($x, $y) = ($x2, $y2);
                $self->{pdf}->move_to($x, $y);
                $need_to_close=1;
            }
            $xoffset = $x; $yoffset = $y;
        }
        else {
            warn("Unknown SVG path command: $type in $data");
        }
    }

    if ($need_to_close) {
        if ($self->{fill} && $self->{stroke}) {
            $self->{pdf}->fill_stroke;
        }
        elsif ($self->{fill}) {
            $self->{pdf}->fill;
        }
        elsif ($self->{stroke}) {
            $self->{pdf}->stroke;
        }
    }
}

sub slide_end_element {
    my ($self, $el) = @_;

    my $name = $el->{LocalName};

    # warn("slide_end_ $name\n");

    $el = $self->{SlideCurrent};
    $self->{SlideCurrent} = $el->{Parent};

    if ($name =~ /^(title|point|source[_-]code)$/) {
        # finish bounding box
        my ($x, $y) = $self->{bb}->get_text_pos;
        $self->{bb}->finish;
        $self->{pdf}->set_text_pos($self->{bb}->{x}, $y - 4);
        my $bb = delete $self->{bb};
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
            x => 20, y => $y + $self->{pdf}->get_value('leading'),
            w => 570, h => 24) if exists($el->{Attributes}{"{}href"});

        $self->{pdf}->set_text_pos(60, $y);
        $self->{chars_ok} = 0;
    }
    elsif ($name eq 'slide') {
        $self->pop_bookmark unless $self->{transitional};
    }
    elsif ($name eq 'i' || $name eq 'b' || $name eq 'span') {
        my $font = pop @{$self->{font_stack}};
        $self->{bb}->set_font(face => $font);
    }
    elsif ($name eq 'point') {
        $self->{chars_ok} = 0;
        my ($x, $y) = $self->{pdf}->get_text_pos();
        $self->{pdf}->add_link(
            link => $el->{Attributes}{"{}href"}{Value},
            x => 20, y => $y + $self->{pdf}->get_value('leading'),
            w => 570, h => 24) if exists($el->{Attributes}{"{}href"});
    }
    elsif ($name eq 'source_code' || $name eq 'source-code') {
        $self->{chars_ok} = 0;
    }
    elsif ($name eq 'image') {
        $self->{image_id}++;
    }
    elsif ($name eq 'colour' || $name eq 'color') {
        pop @{$self->{colour_stack}};
        $self->{bb}->set_colour( rgb => $self->{colour_stack}[-1] );
    }
    elsif ($name eq 'table') {
        shift @{$self->{extents}};
    }
    elsif ($name eq 'row') {
        $self->{row_number}++;
        $self->{pdf}->set_text_pos($self->{row_start}[0], $self->{max_height});
    }
    elsif ($name eq 'col') {
        $self->{col_number}++;
        $self->{pdf}->print_line("");
        my ($x, $y) = $self->{pdf}->get_text_pos;
        # warn("end-col: $y < $self->{max_height} ???");
        $self->{max_height} = $y if $y < $self->{max_height};
    }
    elsif ($name eq 'text') {
        my $text = $self->gathered_text;
        $self->{chars_ok} = 0;
        $self->{pdf}->print($text);
        $self->{pdf}->restore_graphics_state();
        my $font = pop @{$self->{font_stack}};
        # warn("resting font to: $font\n");
        $self->{pdf}->set_font(face => $font);
    }
    elsif ($name =~ /^(circle|ellipse|line|rect|path)$/) {
        $self->{pdf}->restore_graphics_state();
    }
}

sub slide_characters {
    my ($self, $chars) = @_;

    return unless $self->{chars_ok};

    $self->{gathered_text} .= $chars->{Data};

    my $name = $self->{SlideCurrent}->{LocalName};
    my $text = $chars->{Data};
    return unless $text && $self->{bb};
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
points, source code (fixed font) sections, images, SVG vector graphics,
tables, colours, bold and italics, hyperlinks, and transition effects
for all the bullet points, source, and image sections.

=head1 SYNTAX

=head2 <slideshow>

This is the outer element, and must always be present.

=head2 <title>

  <slideshow>
    <title>My First Presentation</title>

The title of the slideshow, used on the first (title) slide.

=head2 <metadata>

  <metadata>
     <speaker>Matt Sergeant</speaker>
     <email>matt@axkit.com</email>
     <organisation>AxKit.com Ltd</organisation>
     <link>http://axkit.com/</link>
     <logo scale="0.4">ax_logo.png</logo>
     <background>redbg.png</background>
  </metadata>

Metadata for the slideshow. Speaker and Organisation are used on the
first (title) slide, and the email and link are turned into hyperlinks.

The background and logo are used on every slide.

=head2 <slideset>

  <slideset>
    <title>A subset of the show</title>
    <subtitle>And a subtitle for it</subtitle>

A slideset groups slides into relevant subsets, with a title and a new
level in the bookmarks for the PDF.

The title and subtitle tags can have C<href> attributes which turn those
texts into links.

=head2 <slide>

  <slide transition="dissolve">
    <title>Introduction</title>
    <point>Perl's XML Capabilities</point>
    <source-code>use XML::SAX;</source-code>
  </slide>

The slide tag defines a single slide. Each top level tag in the slide
can have a C<transition> attribute, which either defines a transition
for the entire slide, or for the individual top level items.

The valid settings for transition are:

=over 4

=item replace

The default. Just replace the old page. Use this on top level page items
to make them appear one by one.

=item split

Two lines sweeping across the screen reveal the page

=item blinds

Multiple lines sweep across the screen to reveal the page

=item box

A box reveals the page

=item wipe

A single line sweaping across the screen reveals the page

=item dissolve

The old page dissolves to reveal the new page

=item glitter

The dissolve effect moves from one screen edge to another

=back

For example, to have each point on a slide reveal themselves
one by one:

  <slide>
    <title>Transitioning Bullet Points</title>
    <point transition="replace">Point 1</point>
    <point transition="replace">Point 2</point>
    <point transition="replace">Final Point</point>
  </slide>

=head2 <point>

The point specifies a bullet point to place on your slide.

The point may have a C<href> attribute, a C<transition> attribute,
and a C<level> attribute. The C<level> attribute defaults to 1, for
a top level bullet point, and can go down as far as you please.

=head2 <source-code> or <source_code>

The source-code tag identifies a piece of verbatim text in a fixed
font - originally designed for source code.

=head2 <image>

The image tag works in one of two ways. For backwards compatibility
it allows you to specify the URI of the image in the text content
of the tag:

  <image>foo.png</image>

Or for compatibility with SVG, you can use xlink:

  <image xlink:href="foo.png"
         xmlns:xlink="http://www.w3.org/1999/xlink"/>

By default, the image is placed centered in the current column
(which is the middle of the slide if you are not using tables) and
at the current text position. However you can override this using
x and y attributes for absolute positioning. You may also specify
a scale attribute to scale the image. Currently absolute width
and height values are not supported, but it is planned to support
them.

The supported image formats are those supported by the underlying
pdflib library: gif, jpg, png and tiff.

=head2 <colour> or <color>

The colour tag specifies a colour for the text to be output. To define
the colour, either use the C<name> attribute, using one of the 16 HTML
named colours, or use the C<rgb> attribute and use a hex triplet
like you can in HTML.

=head2 <i> and <b>

Use these tags for italics and bold within text.

=head2 <table>

  <table>
    <row>
      <col width="40%">
      ...
      </col>
      <col width="60%">
      ...
      </col>
    </row>
  </table>

AxPoint has some rudimentary table support, as you can see above. This
is fairly experimental, and does not do any reflowing like HTML - it
only supports fixed column widths and only as percentages. Using a table
allows you to layout a slide in two columns, and also have multi-row
descriptions of source code with bullet points.

=head1 SVG Support

AxPoint has some SVG support so you can do vector graphics on your slides.

All SVG items allow the C<transition> attribute as defined above.

=head2 <rect>

  <rect x="100" y="100" width="300" height="200"
    style="stroke: blue; stroke-width=5; fill: red"/>

As you can see, AxPoint's SVG support uses CSS to define the style. The
above draws a rectangle with a thick blue line around it, and filled
in red.

=head2 <circle>

  <circle cx="50" cy="100" r="50" style="stroke: black"/>

=head2 <ellipse>

  <ellipse cx="100" cy="50" rx="30" ry="60" style="fill: aqua;"/>

=head2 <line>

  <line x1="50" y1="50" x2="200" y2="200" style="stroke: black;"/>

=head2 <text>

  <text x="200" y="200"
    style="stroke: black; fill: none; font: italic 24pt serif"
  >Some Floating Text</text>

This tag allows you to float text anywhere on the screen.

=head1 BUGS

Please use http://rt.cpan.org/ for reporting bugs.

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

Copyright 2002.

=head1 LICENSE

This is free software, distributed under the same terms as Perl itself.

=cut
