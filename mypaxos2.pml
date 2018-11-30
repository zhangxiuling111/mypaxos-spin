#define ACCEPTORS 3
#define PROPOSERS 5
#define COORDINATORS 3
#define MAJORITY 2

byte leaderno = 0
bool leaderselected = false;
bool progress = false;
bool proposed = false;
byte proposal[PROPOSERS];
byte pcount = 0;

chan coorproposal[COORDINATORS] = [50] of {byte,byte}        /*所有的proposer都先将proposal发送到该通道给coordinator*/
chan prereply[COORDINATORS] = [20] of {byte};                 /*当acceptor的当前round大于coordinator的当前的round值时，acceptor提醒coordinator更大的round值*/
chan accreply[COORDINATORS] = [20] of {byte};
chan acceptorpre[ACCEPTORS] = [20] of {byte,byte};     /*acceptor用来接收prepare信息*/
chan acceptoracc[ACCEPTORS] = [30] of {byte,byte, byte};     /*acceptor用来接收acceptor请求*/
chan promise[COORDINATORS] = [50] of {byte, byte,byte,byte} ;           /*coordinator向acceptor加入round的请求后用来接收promise信息*/
chan learnacc = [50] of {byte,byte,byte};                     /*acceptor接受一个value后发送到该通道用来提醒learner*/
chan learned = [20] of {byte,byte};                          /*learner对同一个value计数超过majority，表示learn到一个value之后则向通道发送被接收的value*/

ltl {<>(progress==1)};

inline laccept(id,round, value){
	byte i;
	for(i : 0 .. (ACCEPTORS-1)){
		acceptoracc[i]!id,round,value;                //向所有的acceptor发送accept请求
	}
	i = 0;
}

inline lprepare(id,round){
	byte i;
	for(i : 0 .. (ACCEPTORS-1)){
		acceptorpre[i] ! id,round;                    //向所有的acceptor发送prepare请求
	}
	i = 0;
}


proctype leader(){                                   //leader election
	select(leaderno : 0 .. (COORDINATORS-1));
	leaderselected = true;                            //确保选出了leader之后再执行coordinator
}

proctype coordinator(byte id){
	byte crnd = 0,cval = 0;
	byte prornd,proval,accrnd ;                       //promise返回的已接收的最高的round，value和acceptor当前的round；
	byte replyrnd;  
	byte val=0;                     				 //proposer 提出的value
	byte accid,proid;               				 //分别为acceptor和proposer的ID
	byte count = 0;
	byte a[ACCEPTORS];
	byte k;

   do
   :: (count < MAJORITY && !progress) ->
	    if 
	    :: promise[id] ? [accid,accrnd,prornd,proval] -> promise[id] ? accid,accrnd,prornd,proval       //查看acceptor返回的promise信息
	        if
	        :: accrnd !=0 && accrnd == crnd -> 
		        if
		        :: a[accid] ==0 ->
		                      d_step{
		                      	if
		                      	:: proval > cval -> cval = proval;
		                      	::else -> skip;
		                      	fi
		                      	a[accid]=1;
		                      	count ++;

		                      }
		        :: a[accid] == 1 -> skip
		        fi
		    fi
		:: atomic {prereply[id] ? [replyrnd]  -> prereply[id] ? replyrnd}    //查看acceptor发送通知信息，即更大的round number,回到初始状态，并清零所有计数
		    if 
		    ::  replyrnd >crnd -> atomic{
		   	  crnd = replyrnd+1;
		   	  for(k : 0 .. ACCEPTORS-1){
		    		a[k] = 0
		    	}
		    	k =0;
		   	  count = 0
		   	  lprepare(id,crnd);
		      }
		  
		    fi
		:: crnd == 0 -> atomic{
		  	 crnd++;
		  	 lprepare(id,crnd)
		  }
		:: else ->skip;
	    fi
   :: count >= MAJORITY ->
      if
      ::atomic{accreply[id] ? [replyrnd] -> accreply[id] ? replyrnd}
	    if 
	    ::replyrnd > crnd -> atomic{
	   	  crnd = replyrnd + 1;
	   	  count = 0;
	   	  for(k : 0 .. ACCEPTORS-1){
		    		a[k] = 0
		    	}
		    	k = 0;
         lprepare(id,crnd);

 	    } 
 	    fi
	  ::(cval == 0  && proposed == true) -> atomic{               //当所有的promise中都没有value值，则coordinator从任意proposer中任意选择一个提出的value；
	  	/*select(proid : 0 .. PROPOSERS-1)
             	  coorproposal[id] ?? eval(proid), val;*/
             do 
             :: coorproposal[id] ? [proid, val] -> coorproposal[id] ? proid, val;
             :: val != 0 -> break;
             od
             cval = val;
     	     laccept(id,crnd,cval)
     	  }
      :: progress == true -> break;
      fi
             	                   
   od

	/*do
	:: atomic{accreply[id] ? [replyrnd] -> accreply[id] ? replyrnd}
	   if replyrnd > crnd -> d_step{
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
	coorproposal[leaderno] ! id,myval;                      //proposer提出proposal，即向相应的coordinator通道中发送value
	if 
	::proposal[id] == 0 -> atomic{
		pcount++;
		proposal[id] = 1;
	}
	  if
	  :: pcount == PROPOSERS -> proposed = true;            //确保proposer都提出了proposal才会选择value发送accept request
	  :: else -> skip;
	  fi                                       
	fi
}


proctype acceptor(byte id){ 
	byte crnd = 0,hrnd = 0,hval = 0;
	byte rnd, val, coorid;
	do
	::  (acceptorpre[id] ? [coorid,rnd] && !progress)->  acceptorpre[id] ? coorid,rnd;  //acceptor查看prepare请求
		if					 
	    :: rnd >= crnd ->atomic{
	    	crnd = rnd
	        promise[coorid] ! id,crnd,hrnd,hval
	    }
	    :: rnd < crnd ->atomic{                                           //若acceptor已参与更大的round，则发送通知信息
	    	prereply[coorid] ! crnd
	    }
	    fi;  
	::  (acceptoracc[id] ? [coorid,rnd,val] && !progress )->acceptoracc[id] ? coorid,rnd,val   //acceptor查看prepare请求
	    if
	    :: rnd >= crnd ->  atomic{
	    	crnd = rnd;
	    	hrnd = rnd;
	    	hval = val;
        	learnacc ! id,crnd,val
	    }
	    :: rnd < crnd -> atomic{                                           //若acceptor已参与更大的round，则发送通知信息
	    	accreply[coorid] ! crnd
	    }
	    :: else -> skip;
	    fi
	:: progress == true -> break;  
	od
}

proctype learner(){
	byte accid,accrnd,accval
	byte crnd = 0
	byte cval
	byte countacc = 0             /*用来记录收到的accept信息*/
	byte lcount[ACCEPTORS]
	byte i;
	do
	::countacc < MAJORITY->
	    if
		:: atomic{learnacc ? [accid,accrnd,accval] ->learnacc ? accid,accrnd,accval}          //learner查看已接受的value并进行计数
		    if 
		    :: crnd == 0 ->d_step{
		    	crnd = accrnd;
		    	cval = accval;
		    	lcount[accid] = 1;
		    	countacc++

		    }
		    :: (crnd == accrnd && lcount[accid] == 0) -> d_step{
		    	assert(accval==cval);             //在同一round中，接收到的value一定相同；
		    	lcount[accid] = 1;
		    	countacc++;

		    }
		    :: (crnd != 0 && crnd < accrnd) -> d_step{               //若接收的round值大于当前round值，则更新round值并初始化所有计数
		    	countacc = 1;
		    	for(i : 0 .. ACCEPTORS-1){
		    		lcount[i] = 0
		    	}
		    	i = 0;
		    	lcount[accid] =1;
		    	crnd = accrnd;
		    	cval = accval;
		    }
		    fi
		fi
    ::countacc >= MAJORITY -> 
             if
             ::progress == true ->break;
             :: else ->
             atomic{
             	learned ! crnd,cval  ;          /*progress*/  //若同一value计数超过majority，则被learn
             	} 
             fi   
    //::progress == true ->break;                  
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
			run proposer(i,i+1)
		}
		run coordinator(leaderno); 
		for(i : 0 .. ACCEPTORS-1){
			run acceptor(i);
		}
		run learner();
		learned ? round,value; 
	    progress = true;
		accvalue = value;
		/*do 
		:: learned ? [round,value] ->learned ? round,value;
		                             assert(value==accvalue);
		:: else -> break;
		od*/

		printf("%d\n",progress);
	}
}
