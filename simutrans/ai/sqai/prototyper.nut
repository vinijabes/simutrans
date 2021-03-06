class cnv_proto_t
{
	weight = 0
	power  = 0
	min_top_speed = 0
	max_speed = 1000000000000
	length = 0
	capacity = 0
	maintenance = 0
	running_cost = 0
	price = 0
	missing_freight = true
	veh = null

	// set by valuator
	nr_convoys = 0

	constructor()
	{
		veh = []
	}

	function append(newveh, freight)
	{
		local cnv = getclass().instance()
		cnv.constructor()

		cnv.veh.extend(veh)
		cnv.veh.append(newveh)
		cnv.weight = weight + freight.get_weight_per_unit() * newveh.get_capacity() + newveh.get_weight()

		cnv.power = power + newveh.get_power()
		cnv.max_speed = min(max_speed, newveh.get_topspeed())
		cnv.length = length + newveh.get_length()

		local fits = newveh.get_freight().is_interchangeable(freight)
		cnv.missing_freight = missing_freight  &&  (newveh.get_capacity()==0  ||  !fits)

		cnv.min_top_speed = convoy_x.calc_max_speed(cnv.power, cnv.weight, cnv.max_speed)
// 		print("XXX Power " +cnv.power + "  weight = " +cnv.weight + " amx = " + cnv.max_speed+ " speed = " + cnv.min_top_speed)
		cnv.capacity = capacity + (fits ? newveh.get_capacity() : 0)
		cnv.maintenance = maintenance + newveh.get_maintenance()
		cnv.running_cost = running_cost + newveh.get_running_cost()
		cnv.price = price + newveh.get_cost()

		return cnv
	}

	static function from_convoy(cnv, freight)
	{
		local p = cnv_proto_t()
		local list = cnv.get_vehicles()
		foreach(v in list) {
			p = p.append(v, freight)
		}
		return p
	}

	function _save()
	{
		return ::saveinstance("cnv_proto_t", this)
	}
}

class prototyper_t extends node_t
{
	wt = 0
	freight = 0
	max_vehicles = 0
	max_length   = 0
	min_speed    = 0

	valuate = null

	best = null
	best_value = 0

	constructor(w, /*string*/f)
	{
		base.constructor("prototyper");
		wt = w
		freight = good_desc_x(f)
	}


	function step()
	{
		local list = vehicle_desc_x.get_available_vehicles(wt)

		local list_first = []
		local list_other = []

		foreach(veh in list) {

			local first = veh.can_be_first()
			local fits  = veh.get_freight().is_interchangeable(freight)
			local pwer  = veh.get_power()>0
			local none  = veh.get_freight().get_name()=="None" || veh.get_capacity()==0

			// use vehicles that can carry freight
			// or that are powered and have no freight capacity
			if (fits ||  (pwer  && none) ) {
				if (first)
					list_first.append(veh)

				list_other.append(veh)
			}

		}

// 		foreach(veh in list_first) print("candidate...leading " + veh.get_name())
// 		foreach(veh in list_other) print("candidate...        " + veh.get_name())

		// array of lists we try to iterate
		local it_lists = []; it_lists.resize(max_vehicles+1)


		local it_ind = [];     it_ind.resize(max_vehicles+1)

		// current convoy candidate - array of desc
		local cnv = [];           cnv.resize(max_vehicles+1)

		// initialize
		cnv[0] =  cnv_proto_t()
		it_ind[1] = -1
		it_lists[1] = list_first

		// iterating ind-th position in convoy
		local ind = 1

		while(true) {

			it_ind[ind] ++
			// done with iterating?
			if (it_ind[ind] >= it_lists[ind].len() ) {
				if (ind>1) {
					ind--
					continue // iterating position ind-1
				}
				else {
					break // end of the iteration
				}
			}

			local test = it_lists[ind][ it_ind[ind] ]

			// check couplings
			if ( ind==1 ? !test.can_be_first() : !vehicle_desc_x.is_coupling_allowed(cnv[ind-1].veh.top(), test) ) {
				continue;
			}
// 			print("Test[" + ind + "] = " + test.get_name())
			// append
			cnv[ind] = cnv[ind-1].append(test, freight)
			local c = cnv[ind]

// 			local ccc = ["weight","power","min_top_speed","max_speed","length","missing_freight", "capacity","maintenance","price","running_cost"]
// 			foreach(key in ccc) print(" ... " + key + " = " + c[key] )

			// check constraints
			// .. length
			local l = (ind > 1 ?  cnv[ind-1].length : 0) + max( CARUNITS_PER_TILE/2, test.get_length());
			if (l > CARUNITS_PER_TILE*max_length) {
				continue;
			}
			// .. more ??

			// check if convoy finished
			if (test.can_be_last()  &&  !c.missing_freight  &&  c.min_top_speed >= min_speed) {
				// evaluate this candidate
				if (valuate) {
					local value = valuate.call(getroottable(), c)
// 					print(" === " + value)
					if (best==null  ||  value > best_value) {
						best = c
						best_value = value
					}
				}
				else {
					// no valuator function -> take first valid convoy and return
					best = c;
					break
				}

// 				print("..... ***")
			}

			// move on to next position
			if (ind >= max_vehicles) {
				continue;
			}

			ind++

			local list_succ = test.get_successors()
			it_lists[ind] = list_succ.len()==0 ? list_other : list_succ
			it_ind[ind] = -1
		}

		if (best) {
			foreach(ind, test in best.veh) {
				print("Best[" + ind + "] = " + test.get_name())
			}

// 			local ccc = ["weight","power","min_top_speed","max_speed","length","missing_freight", "capacity","maintenance","price","running_cost"]
// 			foreach(key in ccc) print(" ... " + key + " = " + best[key] )
//
			return r_t(RT_SUCCESS)
		}
		return r_t(RT_ERROR)
	}

}

class valuator_simple_t {
	wt = 0
	freight = null
	volume = 0 // monthly transport volume
	max_cnvs = 0
	distance = 0

	way_max_speed = -1
	way_maintenance = 0

	function valuate_monthly_transport(cnv) {

		local speed = way_max_speed > 0 ? min(way_max_speed, cnv.min_top_speed) : cnv.min_top_speed

		local frev = good_desc_x(freight).calc_revenue(wt, speed)

		local capacity = cnv.capacity
		// tiles per month of one convoy
		local tpm = convoy_x.speed_to_tiles_per_month(speed) / 2 + 1

		// needed convoys to transport everything
		local n1 = max(1, volume * 2 * distance / (tpm * cnv.capacity))

		// realistic number of convoys
		local ncnv = min(n1, min(max_cnvs, max(distance / 8, 3) ) )
		cnv.nr_convoys = ncnv

		if (way_max_speed > 0) {
			// correction factor to prefer faster ways:
			// factor = 0 .. if 2*distance < ncnv
			// factor = 1 .. if distance/3 > ncnv
			// linear interpolated in between
			// without scaling almost always the cheapest way is chosen ...
			local factor = max(0, min(10*distance, 6*(2*distance - ncnv) ) );
			// rescale tiles per month
			tpm = (tpm*factor) / (10*distance);
		}

		// monthly costs and revenue
		local value = ncnv*( (frev*cnv.capacity+1500)/3000*tpm - cnv.running_cost*tpm - cnv.maintenance) - distance * way_maintenance

		return value
	}

	function _save()
	{
		return ::saveinstance("valuator_simple_t", this)
	}
}
