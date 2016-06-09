use common::sense;
use Tk;
use Win32::GUI;

my $MAX_COLS         = 10 ;       # 10 cells wide
my $MAX_ROWS         = 15;       # 15 cells high
my $TILE_WIDTH       = 42;        # width of each tile in pixels 
my $TILE_HEIGHT      = 42;        # height of each tile in pixels 

my $shoot_row        = int($MAX_ROWS/2);
my @cells = ();
my @tile_ids = ();

# Widgets
my $w_start;                              # start button widget
my $w_top;                                # top level widget
my $w_heap;                               # canvas
my $w_splash;                             # help
my $score = 0;

my $interval = 250; # in milliseconds
my @heap = ();                            # An element of the heap contains
                                          # a tile-id if that cell is
                                          # filled
$heap[$MAX_COLS * $MAX_ROWS - 1] = undef; # presize
# States
my $START = 0;
my $PAUSED = 1;
my $RUNNING = 2;
my $GAMEOVER = 4;
my $state = $PAUSED;

sub tick {
    return if ($state == $PAUSED);

    if (!@cells) {
        if (!create_random_block()) {
            game_over();              # Heap is full:could not place block
            return;                   # at next tick interval
        }
        $w_top->after($interval, \&tick);
        return;
    }
    move_down();                      # move the block down
    $w_top->after($interval, \&tick); # reload timer for nex

}

sub fall {                 # Called when spacebar hit    
    return if (!@cells);   # Return if not initialized
    1 while (move_down()); # Move down until it hits the heap or bottom.
}

sub move_left {
    my $cell;
    foreach $cell (@cells) {
        # Check if cell is at the left edge already
        # If not, check whether the cell to its left is already occupied.
        if ((($cell % $MAX_COLS) == 0) ||
            ($heap[$cell-1])){
            return;
        }
    }

    foreach $cell (@cells) {
        $cell--; # This affects the contents of @cells
    }
    
    $w_heap->move('block', - $TILE_WIDTH, 0);
}


sub move_right {
    my $cell;
    
    foreach $cell (@cells) {
        # Check if cell is at the right edge already
        # If not, check whether the cell to its right is already occupied.
        if (((($cell+1) % $MAX_COLS) == 0) ||
            ($heap[$cell+1])){
            return;
        }
    }

    foreach $cell (@cells) {
        $cell++; # This affects the contents of @cells
    }
    
    $w_heap->move('block', $TILE_WIDTH, 0);
}

sub move_down {
    my $cell;

    my $first_cell_last_row = ($MAX_ROWS-1)*$MAX_COLS;
    # if already at the bottom of the heap, or if a move down
    # intersects with the heap, then merge both.
    foreach $cell (@cells) {
        if (($cell >= $first_cell_last_row) ||
            ($heap[$cell+$MAX_COLS])) {
            merge_block_and_heap();
            return 0;
        }
    }

    foreach  $cell (@cells) {
        $cell += $MAX_COLS;
    }

    $w_heap->move('block', 0,  $TILE_HEIGHT);

    return 1;
}

sub rotate {
    # rotates the block counter_clockwise
    return if (!@cells);
    my $cell;
    # Calculate the pivot position around which to turn
    # The pivot is at (average x, average y) of all cells
    my $row_total = 0; my $col_total = 0;
    my ($row, $col);
    my @cols = map {$_ % $MAX_COLS} @cells;
    my @rows = map {int($_ / $MAX_COLS)} @cells;
    foreach (0 .. $#cols) {
        $row_total += $rows[$_];
        $col_total += $cols[$_];
    }
    my $pivot_row = int ($row_total / @cols + 0.5); # pivot row
    my $pivot_col = int ($col_total / @cols + 0.5); # pivot col
    # To position each cell counter_clockwise, we need to do a small
    # transformation. A row offset from the pivot becomes an equivalent 
    # column offset, and a column offset becomes a negative row offset.
    my @new_cells = ();
    my @new_rows = ();
    my @new_cols = ();
    my ($new_row, $new_col);
    while (@rows) {
        $row = shift @rows;
        $col = shift @cols;
        # Calculate new $row and $col
        $new_col = $pivot_col + ($row - $pivot_row);
        $new_row = $pivot_row - ($col - $pivot_col);
        $cell = $new_row * $MAX_COLS + $new_col;
        # Check if the new row and col are invalid (is outside or something
        # is already occupying that  cell)
        # If valid, then no-one should be occupying it.
        if (($new_row < 0) || ($new_row > $MAX_ROWS) ||
            ($new_col < 0) || ($new_col > $MAX_COLS)  ||
            $heap[$cell]) {
            return 0;
        }
        push (@new_rows, $new_row);
        push (@new_cols, $new_col);
        push (@new_cells, $cell);
    }
    # Move the UI tiles to the appropriate coordinates
    my $i= @new_rows-1;
    while ($i >= 0) {
        $new_row = $new_rows[$i];
        $new_col = $new_cols[$i];
        $w_heap->coords($tile_ids[$i],
                        $new_col * $TILE_WIDTH,      #x0
                        $new_row * $TILE_HEIGHT,     #y0
                        ($new_col+1) * $TILE_WIDTH,  #x1
                        ($new_row+1) * $TILE_HEIGHT);
        $i--;
    }
    @cells = @new_cells;
    1; # Success
}


sub set_state {
    $state = $_[0];
    if ($state == $PAUSED) {
        # $w_start->configure ('-text' => 'Resume');
    } elsif ($state == $RUNNING) {
        # $w_start->configure ('-text' => 'Pause');
    } elsif ($state == $GAMEOVER) {
        $w_heap->itemconfigure ('all',
                                '-stipple' => 'gray25');
    } elsif ($state == $START) {
        # $w_start->configure ('-text' => 'Start');
    }
}
sub start_pause {
    if ($state == $RUNNING) {
        set_state($PAUSED);
    } else {
        if ($state == $GAMEOVER) {
            new_game();
        }
        set_state($RUNNING);
        tick();
    }
}

sub new_game() {
    $w_heap->delete('all');
    @heap = ();
    @cells = ();
    show_heap();
    $score = 0;
}

sub bind_key {
    my ($keychar, $callback) = @_;    
    $w_top->bind("<KeyPress-${keychar}>", $callback) if (length($keychar) > 1);
    $w_top->bind("<${keychar}>", $callback) if (length($keychar) == 1);
}

sub merge_block_and_heap {
    my $cell;
    # merge block
    foreach $cell (@cells) {
        $heap[$cell] = shift @tile_ids;
    }
    $w_heap->dtag('block'); # Forget about the block - it is now merged 

    # check for full rows, and get rid of them
    # All rows above them need to be moved down, both in @heap and 
    # the canvas, $w_heap
    my $last_cell = $MAX_ROWS * $MAX_COLS;

    my $filled_cell_count;
    my $rows_to_be_deleted = 0;
    my $i;

    for ($cell = 0; $cell < $last_cell; ) {
        $filled_cell_count = 0;
        my $first_cell_in_row = $cell;
        for ($i = 0; $i < $MAX_COLS; $i++) {
            $filled_cell_count++ if ($heap[$cell++]);
        }
        if ($filled_cell_count == $MAX_COLS) {
            # this row is full
            for ($i = $first_cell_in_row; $i < $cell; $i++) {
                $w_heap->addtag('delete', 'withtag' => $heap[$i]);
            }
            splice(@heap, $first_cell_in_row, $MAX_COLS);
            unshift (@heap, (undef) x $MAX_COLS);
            $rows_to_be_deleted = 1;
            $score++;
            my $fmt_score = sprintf("%03i", $score);
            $w_top->title("Falling Blocks (${fmt_score})");
        }
    }

    @cells = ();
    @tile_ids = ();
    if ($rows_to_be_deleted) {
        $w_heap->itemconfigure('delete', 
                               '-fill'=> 'white');
        $w_top->after (300, 
                       sub {
                           $w_heap->delete('delete');
                           my ($i);
                           my $last = $MAX_COLS * $MAX_ROWS;
                           for ($i = 0; $i < $last; $i++) {
                               next if !$heap[$i];
                               # get where they are
                               my $col = $i % $MAX_COLS;
                               my $row = int($i / $MAX_COLS);
                               $w_heap->coords(
                                    $heap[$i],
                                    $col * $TILE_WIDTH,       #x0
                                    $row * $TILE_HEIGHT,      #y0
                                    ($col+1) * $TILE_WIDTH,   #x1
                                    ($row+1) * $TILE_HEIGHT); #y1

                           }
                       });
    }
}

sub show_heap {
    my $i;
    foreach $i (1 .. $MAX_ROWS) {
        $w_heap->create('line',
                        0,
                        $i*$TILE_HEIGHT,
                        $MAX_COLS*$TILE_WIDTH,
                        $i*$TILE_HEIGHT,
                        '-fill' => '#2D2D2D'
                        );
    }
    foreach $i (1 .. $MAX_COLS) {
        $w_heap->create('line',
                        $i*$TILE_WIDTH,
                        0,
                        $i*$TILE_WIDTH,
                        $MAX_ROWS * $TILE_HEIGHT,
                        '-fill' => '#2D2D2D'
                        );
    }

}

my @patterns = (
                [
                 " * ",
                 "***"
                 ],
                [
                 "****"
                 ],
                [
                 "  *",
                 "***"
                 ],
                [
                 "*  ",
                 "***"
                 ],
                 [
                 " **",
                 "** "
                 ],
                 [                 
                 "** ",
                 " **"
                 ],
                [
                 "**",
                 "**"
                 ]
                );
my @colors = (
              '#413E4A', '#73626E', '#B38184', 
              '#F0B49E', '#F7E4BE', '#FF847C'
              );


sub game_over {
    set_state($GAMEOVER);
}

sub create_random_block {
    # choose a random pattern, a random color, and position the 
    # block at the top of the heap.
    my $pattern_index = int(rand (scalar(@patterns)));
    my $color   = $colors[int(rand (scalar (@colors)))];
    my $pattern = $patterns[$pattern_index];
    my $pattern_width = length($pattern->[0]);
    my $pattern_height = scalar(@{$pattern});
    my $row = 0;  my $col = 0;
    my $base_col = int(($MAX_COLS - $pattern_width) / 2);
    while (1) {
        if ($col == $pattern_width) {
            $row++; $col = 0;
        }
        last if ($row == $pattern_height);
        if (substr($pattern->[$row], $col, 1) ne ' ') {
            push (@cells, $row * $MAX_COLS + $col + $base_col);
        }
        $col++;
    }
    $col = 0;
    my $cell;
    foreach $cell (@cells) {
        # If something already exists where the block is supposed
        # to be, return false
        return 0 if ($heap[$cell]);
    }

    $col = 0;
    foreach $cell (@cells) {
        create_tile($cell, $color);
    }
    return 1;
}

sub create_tile {
    my ($cell, $color) = @_;
    my ($row, $col);
    $col = $cell % $MAX_COLS;
    $row = int($cell / $MAX_COLS);
    push (@tile_ids, 
          $w_heap->create('rectangle',
                          $col * $TILE_WIDTH,      #x0
                          $row * $TILE_HEIGHT,     #y0
                          ($col+1) * $TILE_WIDTH,  #x1
                          ($row+1) * $TILE_HEIGHT, #y1
                          '-fill' => $color,
                          '-tags' => 'block'
                          )
          );
}

sub quit_game {
    exit(0);
}

sub new_splash {
    $w_splash = MainWindow->new(-background => '#282828');
    $w_splash->title('Falling Blocks -- Help');
    $w_splash->Label(-text => " Falling Blocks",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "------------------------",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => " ",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tUp\t-\tRotate current game piece",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tLeft\t-\tMove current game piece left",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tRight\t-\tMove current game piece right",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tDown\t-\tDrop current game piece to ground",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => " ",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tSpace\t-\tPause current game",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tEnter\t-\tBegin a new game",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => " ",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => "\tF1\t-\tHelp Screen",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
    $w_splash->Label(-text => " ",-background => '#282828')->pack(-side => 'top', -anchor => 'nw');
}

my $i_splash = 0;

sub help_dec {
    $i_splash = 0;
    $w_splash = undef;
}

sub help {        
    $w_splash = new_splash unless $i_splash == 1;
    $i_splash = 1;
    $w_splash->bind('<Destroy>', \&help_dec);    
}

sub init {
    # hide Win32 Debugging Console
    my $hw = Win32::GUI::GetPerlWindow();
    Win32::GUI::Hide($hw);

    create_screen();
    bind_key('Left', \&move_left);
    bind_key('Right', \&move_right);
    bind_key('Down', \&fall);
    bind_key('Up', \&rotate);
    bind_key('space', \&start_pause);
    bind_key('Return', \&new_game);
    bind_key('Escape', \&quit_game);
    bind_key('F1', \&help);
    bind_key('question', \&help);
    srand();
    set_state($START);
    new_game();
}

sub create_screen {
    $w_top = MainWindow->new;
    my $fmt_score = sprintf("%03i", $score);
    $w_top->title("Falling Blocks (${fmt_score})");
    $w_top->maxsize(($MAX_COLS) * $TILE_WIDTH, ($MAX_ROWS)* $TILE_HEIGHT);
    $w_top->minsize(($MAX_COLS) * $TILE_WIDTH, ($MAX_ROWS) * $TILE_HEIGHT);
    $w_top->geometry(sprintf('%dx%d', ($MAX_COLS - 1) * $TILE_WIDTH, ($MAX_ROWS - 1) * $TILE_HEIGHT));
    
    $w_heap = $w_top->Canvas('-width'  => $MAX_COLS * $TILE_WIDTH,
                             '-height' => $MAX_ROWS  * $TILE_HEIGHT,
                             '-border' => 1,
                             '-relief' => 'ridge',                             
                             '-background' => '#282828');
    $w_heap->pack();
}

init();
MainLoop();
