package SL::DB::Manager::OrderItem;

use strict;

use SL::DB::Helper::Manager;
use base qw(SL::DB::Helper::Manager);

use SL::DB::Helper::Paginated;
use SL::DB::Helper::Sorted;

sub object_class { 'SL::DB::OrderItem' }

__PACKAGE__->make_manager_methods;

sub _sort_spec {
  return ( columns => { delivery_date => [ 'deliverydate',        ],
                        description   => [ 'lower(orderitems.description)',  ],
                        partnumber    => [ 'part.partnumber',     ],
                        qty           => [ 'qty'                  ],
                        ordnumber     => [ 'order.ordnumber'      ],
                        customer      => [ 'lower(customer.name)', ],
                        position      => [ 'trans_id', 'runningnumber' ],
                        reqdate       => [ 'COALESCE(orderitems.reqdate, order.reqdate)' ],
                        orddate       => [ 'order.orddate' ],
                        sellprice     => [ 'sellprice' ],
                        discount      => [ 'discount' ],
                        transdate     => [ 'orderitems.transdate::date', 'order.reqdate' ],
                      },
           default => [ 'position', 1 ],
           nulls   => { }
         );
}

sub default_objects_per_page { 40 }

1;
