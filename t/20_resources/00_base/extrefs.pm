# vim: ts=2 sw=2 expandtab
use strict;

use lib qw(./mylib ../mylib);
use Test::More tests => 31;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

BEGIN {
  package POE::Kernel;
  use constant TRACE_DEFAULT => exists($INC{'Devel/Cover.pm'});
}

BEGIN { use_ok("POE") }

# Base reference count.
my $base_refcount = 0;

# Increment an extra reference count, and verify its value.

my $kr_extra_refs = $poe_kernel->[POE::Kernel::KR_EXTRA_REFS()];

my $refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-1");
is($refcnt, 1, "tag-1 incremented to 1");

$refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-1");
is($refcnt, 2, "tag-1 incremented to 2");

# Baseline plus one reference: tag-1.  (No matter how many times you
# increment a single tag, it only counts as one session reference.
# This may change if the utility of the reference counts adding up
# outweighs the overhead of managing the session reference more.)

is(
  $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 1,
  "POE::Kernel properly counts tag-1 extra reference"
);

# Attempt to remove some strange tag.

eval { $kr_extra_refs->remove($poe_kernel->ID, "nonexistent") };
ok(
  $@ && $@ =~ /removing extref for nonexistent tag/,
  "can't remove nonexistent tag from a session"
);

is(
  $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 1,
  "POE::Kernel reference count unchanged"
);

# Remove it entirely, and verify that it's 1 again after incrementing
# again.

$kr_extra_refs->remove($poe_kernel->ID, "tag-1");
is(
  $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 0,
  "clear reset reference count to baseline"
);

$refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-1");
is($refcnt, 1, "tag-1 count cleared/incremented to 1");
is(
  $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 1,
  "increment after clear"
);

# Set a second reference count, then verify that both are reset.

$refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-2");
is($refcnt, 1, "tag-2 incremented to 1");

# Setting a second tag increments the master reference count.

is(
  $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 2,
  "POE::Kernel reference count incremented with new tag"
);

# Clear all the extra references for the session, and verify that the
# master reference count is back to the baseline.

$kr_extra_refs->clear_session($poe_kernel->ID);
is(
  $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount,
  "clearing all extrefs brings count to baseline"
);

eval { $kr_extra_refs->remove($poe_kernel->ID, "nonexistent") };
ok(
  $@ && $@ =~ /removing extref from session without any/,
  "can't remove tag from a session without any"
);

$refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-1");
is($refcnt, 1, "tag-1 incremented back to 1");

$refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-2");
is($refcnt, 1, "tag-2 incremented back to 1");

$refcnt = $kr_extra_refs->increment($poe_kernel->ID, "tag-2");
is($refcnt, 2, "tag-2 incremented back to 2");

# Only one session has an extra reference count.

is(
  $kr_extra_refs->count_sessions(), 1,
  "only one session has extra references"
);

# Extra references for the kernel should be two.  A nonexistent
# session should have none.

is(
  $kr_extra_refs->count_session_refs($poe_kernel->ID), 2,
  "POE::Kernel has two extra references"
);

is(
  $kr_extra_refs->count_session_refs("nothing"), 0,
  "nonexistent session has no extra references"
);

# What happens if decrementing an extra reference for a tag that
# doesn't exist?

eval { $kr_extra_refs->decrement($poe_kernel->ID, "nonexistent") };
ok(
  $@ && $@ =~ /decrementing extref for nonexistent tag/,
  "can't decrement an extref if a session doesn't have it"
);

# Clear the references, and make sure the subsystem shuts down
# cleanly.

{ is(
    $kr_extra_refs->decrement($poe_kernel->ID, "tag-1"), 0,
    "tag-1 decremented to 0"
  );

  is(
    $kr_extra_refs->count_session_refs($poe_kernel->ID), 1,
    "POE::Kernel has one extra reference"
  );

  is(
    $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 1,
    "POE::Kernel reference count decremented along with tag"
  );
}

{ is(
    $kr_extra_refs->decrement($poe_kernel->ID, "tag-2"), 1,
    "tag-2 decremented to 1"
  );

  is(
    $kr_extra_refs->count_session_refs($poe_kernel->ID), 1,
    "POE::Kernel still has one extra reference"
  );

  is(
    $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount + 1,
    "POE::Kernel reference count not decremented yet"
  );
}

{ is(
    $kr_extra_refs->decrement($poe_kernel->ID, "tag-2"), 0,
    "tag-2 decremented to 0"
  );

  is(
    $kr_extra_refs->count_session_refs($poe_kernel->ID), 0,
    "POE::Kernel has no extra references"
  );

  is(
    $poe_kernel->_data_ses_refcount($poe_kernel->ID), $base_refcount,
    "POE::Kernel reference count decremented again"
  );
}

# Catch some errors.

eval { $kr_extra_refs->decrement($poe_kernel->ID, "nonexistent") };
ok(
  $@ && $@ =~ /decrementing extref for session without any/,
  "can't decrement an extref if a session doesn't have any"
);

# Clear the session again, to exercise some code that otherwise
# wouldn't be.

$kr_extra_refs->clear_session($poe_kernel->ID);

# Ensure the subsystem shuts down ok.

ok(
  $kr_extra_refs->finalize(),
  "POE::Resource::Extrefs finalized ok"
);

1;
