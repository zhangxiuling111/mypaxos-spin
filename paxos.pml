#define ACCEPTORS 3
#define PROPOSERS 5
#define COORDINATORS 3
#define MAJORITY 2

byte leaderno = 0
bool leaderselected = false;
bool progress = false;

chan coorproposal[COORDINATORS] = [100] of {byte,byte}        /*?有的proposer都先将proposal????????道给coordinator*/
chan preack[COORDINATORS] = [100] of {byte}                 /*当acceptor的当前round大于coordinator???的round值时，acceptor????coordinator更大的round?*/
chan accack[COORDINATORS] = [100] of {byte}
chan acceptorpre[ACCEPTORS] = [100] of {byte,byte};     /*acceptor用来接收prepare信息*/
chan acceptoracc[ACCEPTORS] = [100] of {byte,byte, byte};     /*acceptor用来接收acceptor请求*/
chan promise[COORDINATORS] = [100] of {byte, byte,byte,byte}            /*coordinator向acceptor?????round???求后用来接收promise信息*/
chan learnacc = [100] of {byte,byte,byte}                     /*acceptor接受?个value后发送到???道用来提醒learner*/
chan learned = [100] of {byte,byte}                          /*learner对同一个value计数超过majority，表示learn到一个value之后则向???道发????*/

inline laccept(id,round, value){
	byte i;
	for(i : 0 .. (ACCEPTORS-1)){
		acceptoracc[i]!id,round,value;
	}
	i = 0;
}

inline lprepare(id,round){
	byte i;
	for(i : 0 .. (ACCEPTORS-1)){
		acceptorpre[i] ! id,round;
	}
	i = 0;

}


proctype leader(){
	select(leaderno : 0 .. (COORDINATORS-1));
	leaderselected = true;
	


}

proctype coordinator(byte id){
	byte crnd = 0,cval = 0;
	byte prornd,proval,accrnd ;      //promise返回的已接收的最高的round，value和acceptor当前的round；
	byte ackrnd;
	byte val;                //proposer 提出的value
	byte accid,proid;        //分别为acceptor和proposer的ID
	byte count = 0;
	byte a[ACCEPTORS];

   do
   :: count < MAJORITY && !progress ->
	    if 
	    :: promise[id] ? [accid,accrnd,prornd,proval] -> promise[id] ? accid,accrnd,prornd,proval
	        if
	        :: accrnd !=0 && accrnd == crnd -> 
		        if
		        :: a[accid] ==0 ->
		                      d_step{
		                      	cval = proval;
		                      	a[accid]=1;
		                      	count ++;

		                      }
		        :: a[accid] == 1 -> skip
		        fi
		    fi
		:: atomic {preack[id] ? [ackrnd]  -> preack[id] ? ackrnd}
		    if 
		    ::  ackrnd >crnd -> atomic{
		   	  crnd = ackrnd+1;
		   	  count = 0
		   	  lprepare(id,crnd);
		      }
		  
		    fi
		:: crnd == 0 -> atomic{
		  	 crnd++;
		  	 lprepare(id,crnd)
		  }
		:: else ->atomic{lprepare(id,crnd)};
	    fi
   :: count >= MAJORITY && !progress->
      if
      ::atomic{accack[id] ? [ackrnd] -> accack[id] ? ackrnd}
	    if 
	    ::ackrnd > crnd -> atomic{
	   	  crnd = ackrnd + 1;
         lprepare(id,crnd);

 	    } 
 	    fi
	  ::else-> atomic{
                if 
             	:: cval = 0 ->/*select(proid : 0 .. PROPOSERS-1)
             	             coorproposal[id] ?? eval(proid), val;*/
             	             do
             	             :: coorproposal[id] ? [proid, val] -> coorproposal[id] ? proid, val;
             	             :: break;
             	             od

             	             cval = val
             	fi
             	laccept(id,crnd,cval)
                }
      fi
   :: progress == true -> break;                    
  
   od

	/*do
	:: atomic{accack[id] ? [ackrnd] -> accack[id] ? ackrnd}
	   if ackrnd > crnd -> d_step{
	   	crnd = accrnd + 1;
        lprepare(id,crnd);
 	   } 
 	od*/


}

proctype proposer(byte id; byte myval)
{
	/*byte prornd,proval
	byte count = 0;
	byte a[ACCEPTORS]*/
	coorproposal[leaderno] ! id,myval;

}


proctype acceptor(byte id){ 
	byte crnd = 0,hrnd = 0,hval = 0;
	byte rnd, val, coorid,accid;
	do
	::  acceptorpre[id] ? [coorid,rnd] && !progress->  acceptorpre[id] ? coorid,rnd;
		if					 
	    :: rnd >= crnd ->atomic{
	    	crnd = rnd
	        promise[coorid] ! id,crnd,hrnd,hval
	    }
	    :: rnd < crnd ->atomic{
	    	preack[coorid] ! crnd
	    }
	    fi;  
	::  acceptoracc[id] ? [accid,rnd,val] && !progress ->acceptoracc[id] ? accid,rnd,val
	    if
	    :: rnd >= crnd ->  atomic{
	    	crnd = rnd;
	    	hrnd = rnd;
	    	hval = val;
	    	learnacc ! id,crnd,val
	    }
	    :: rnd < crnd -> atomic{
	    	accack[coorid] ! crnd
	    }
	    fi
	:: progress == true -> break;  
	od

	

}

proctype learn(){
	byte accid,accrnd,accval
	byte crnd = 0
	byte cval
	byte countacc = 0             /*用来记录收到的accept信息*/
	byte lcount[ACCEPTORS]
	byte i
	do
	::countacc < MAJORITY->
	    if
		:: atomic{learnacc ? [accid,accrnd,accval] ->learnacc ? accid,accrnd,accval}
		    if 
		    :: crnd == 0 ->d_step{
		    	crnd = accrnd;
		    	cval = accval;
		    	lcount[accid] = 1;
		    	countacc++

		    }
		    :: crnd == accrnd && lcount[accid] == 0 ->d_step{
		    	assert(accval==cval);             //在同一round中，接收到的value一定相同；
		    	lcount[accid] = 1;
		    	countacc++;

		    }
		    :: crnd != 0 && crnd < accrnd->d_step{
		    	countacc = 1;
		    	for(i : 0 .. ACCEPTORS-1){
		    		lcount[i] = 0
		    	}
		    	lcount[accid] =1;
		    	crnd = accrnd;
		    	cval = accval;
		    }
		    fi
		fi
    ::countacc >= MAJORITY -> 
             atomic{
             	learned ! crnd,cval  ;          /*progress*/
             	break;
             	}                      
    od
}



init
{
	byte i,round,value;
	atomic{
		byte accvalue;
		run leader();
		leaderselected == true;
		for(i : 0 .. PROPOSERS-1){
			run proposer(i,i)
		}
		run coordinator(leaderno); 
		for(i : 0 .. ACCEPTORS-1){
			run acceptor(i);
		}
		run learn();
		learned ? round,value; 
	    progress = true;
		accvalue = value;
		do 
		:: learned ? [round,value] ->learned ? round,value;
		                             assert(value==accvalue);
		:: else -> break;
		od

		printf("%d\n",progress);
	}
}
