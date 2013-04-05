/**
* saves selected training population ids to cookie
* @author Isaak Y Tecle <iyt2@cornell.edu>
*
*/

JSAN.use("jquery");
JSAN.use("Prototype");

var popIds = []; 

var getPopIds =  function() {
    jQuery("input:checkbox[name='project']").change(function() {         
            
            if (jQuery(this).attr('checked')) {
              
                var popId;
                var indexPopId; 
                var trId = traitId();
                popId = jQuery(this).val();
               
                //var len = popIds.length;
                if (popIds.length < 1 ) {
                    popIds.push(popId); 
                   
                    var cookieArrayData = [];
                    var cookieData = jQuery.cookie('trait_populations');
                   alert('there is cookie:' + cookieData);
                   if (cookieData) {
                       cookieArrayData = cookieData.split(","); 
                       cookieArrayData.push(popId);
                       jQuery.cookie('trait_populations', cookieArrayData);
                    // var cookieData =  jQuery.cookie('trait_populations');
                    // cookieArrayData = cookieData.split(",");
                   }else {
                       jQuery.cookie('trait_populations', popIds);
                   }
                    if (cookieArrayData instanceof Array) {
                        alert('cookie is an array');
                    }
                    alert('tr id '+ trId + ' cookie: '+ cookieArrayData + ' len:' + popIds.length + 'id: '+popId+' ids: '+ popIds);
                }
                else {
                    indexPopId = jQuery.inArray(popId, popIds);
                    if (indexPopId == -1) {                       
                        popIds.push(popId);
                        // popIds = popIds.unique();
                        var cookieArrayData = popIds;
                        jQuery.cookie('trait_populations', popIds);
                        var cookieData =  jQuery.cookie('trait_populations');
                        
                        alert('cokie: '+ cookieArrayData +'len: ' + popIds.length + 
                              ' index: ' + indexPopId + ' id: '+popId+' ids: '+ popIds
                              );
                    }
                }
            }
            else  {               
                var popId = jQuery(this).val();
                var cookieArrayData = [];
                var cookieData =  jQuery.cookie('trait_populations');
                cookieArrayData = cookieData.split(",");
              
                var indexPopId = jQuery.inArray(popId, cookieArrayData);
                
                if(indexPopId != -1) {
                    cookieArrayData.splice(indexPopId, 1);
                } 
                alert('cookie: '+ cookieArrayData +'len: ' + cookieArrayData.length + 
                      ' index: ' + indexPopId + ' id: '+popId);
                cookieArrayData = cookieArrayData.unique();
                jQuery.cookie('trait_populations', cookieArrayData);
          
             }
         
          
           jQuery('#select_done').click(function() {
                   // alert(popIds);
                });

           
            

        });
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


var traitId = function () {
   var id = jQuery("input[name='trait_id']").val();
   return id;
};
