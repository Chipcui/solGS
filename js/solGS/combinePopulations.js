/**
* saves selected training population ids to cookie
* @author Isaak Y Tecle <iyt2@cornell.edu>
*
*/

JSAN.use("jquery");
JSAN.use("Prototype");


var popIds = [];


var getCookieName =  function (trId) {
    return 'trait_' + trId + '_populations';
};

var getPopIds =  function() {
    jQuery("input:checkbox[name='project']").change(function() {
            
            var trId = getTraitId(); 
            var cookieName = getCookieName(trId);
            
            if (jQuery(this).attr('checked')) {
              
                var popId;
                var indexPopId; 
               
                popId = jQuery(this).val();
               
                //var len = popIds.length;
                if (popIds.length < 1 ) {
                    popIds.push(popId); 
                    
                    var cookieArrayData = [];
                    var cookieData = jQuery.cookie(cookieName);
                   alert('there is cookie:' + cookieName + '_' + cookieData);
                   if (cookieData) {
                       cookieArrayData = cookieData.split(","); 
                       cookieArrayData.push(popId);
                       jQuery.cookie(cookieName, cookieArrayData);
                   }else {
                       jQuery.cookie(cookieName, popIds);
                   }
                   if (cookieArrayData instanceof Array) {
                       alert('cookie is an array');
                   }
                   alert('tr id '+ trId + ' cookie: '+ cookieArrayData + 
                         ' len:' + popIds.length + 'id: '+popId+' ids: '
                         + popIds);
                }
                else {
                    indexPopId = jQuery.inArray(popId, popIds);
                    if (indexPopId == -1) {                       
                        popIds.push(popId);
                        // popIds = popIds.unique();
                        var cookieArrayData = popIds;
                        jQuery.cookie(cookieName, popIds);
                        var cookieData =  jQuery.cookie(cookieName);
                        
                        alert('cokie: '+ cookieArrayData +'len: ' + popIds.length + 
                              ' index: ' + indexPopId + ' id: '+popId+' ids: '+ popIds
                              );
                    }
                }
            }
            else  {               
                var popId = jQuery(this).val();
                var cookieArrayData = [];
                var cookieData =  jQuery.cookie(cookieName);
                cookieArrayData = cookieData.split(",");
              
                var indexPopId = jQuery.inArray(popId, cookieArrayData);
                
                if(indexPopId != -1) {
                    cookieArrayData.splice(indexPopId, 1);
                } 
                alert('cookie: '+ cookieArrayData +'len: ' + cookieArrayData.length + 
                      ' index: ' + indexPopId + ' id: '+popId);
                cookieArrayData = cookieArrayData.unique();
                jQuery.cookie(cookieName, cookieArrayData);
          
             }          
        });
    };


var selectedPops = function () {
            var trId       = getTraitId();
            var cookieName = getCookieName(trId);
            var cookieData = jQuery.cookie(cookieName);
            var cookieArrayData = [];

            if (cookieData) {
                cookieArrayData = cookieData.split(",");
                cookieArrayData = cookieArrayData.unique();
            }
            
            alert('submited pops: ' +  cookieArrayData);
            if( cookieArrayData.length > 0 ) {
            
                var action = "/combine/populations/trait/" + trId;
                var pops = trId + "=" + cookieArrayData;
                jQuery.ajax({  
                        type: 'POST',
                        dataType: "json",
                        url: action,
                        data: pops,
                        success: function(res){                       
                              var suc = res.status;
                          }
                    });
            }
            else {
                alert('No populations were selected.' +
                      'Please make your selections.'
                      );

            }

};
 

 
Array.prototype.unique =
    function() {
    var a = [];
    var l = this.length;
    for(var i=0; i<l; i++) {
      for(var j=i+1; j<l; j++) {
        // If this[i] is found later in the array
        if (this[i] === this[j])
          j = ++i;
      }
      a.push(this[i]);
    }
    return a;
  };


var getTraitId = function () {
   var id = jQuery("input[name='trait_id']").val();
   return id;
};



