var TableDatatablesButtons = function () {

    var initTable1 = function () {
        var table = $('#sample_1');
        if (!table.length) return;

        var oTable = table.dataTable({

            "language": {
                "aria": {
                    "sortAscending": ": activate to sort column ascending",
                    "sortDescending": ": activate to sort column descending"
                },
                "emptyTable": "No data available in table",
                "info": "Showing _START_ to _END_ of _TOTAL_ entries",
                "infoEmpty": "No entries found",
                "infoFiltered": "(filtered from _MAX_ total entries)",
                "lengthMenu": "_MENU_ entries",
                "search": "Search:",
                "zeroRecords": "No matching records found"
            },

            buttons: [
                { extend: 'copy', className: 'btn red btn-outline' },
                { 
                    extend: 'pdf', 
                    className: 'btn green btn-outline',
                    exportOptions: {
                        modifier: {
                            search: 'none',
                            order: 'current',
                            page: 'all'
                        }
                    },
                    orientation: 'landscape',
                    pageSize: 'A4',
                    filename: 'reporte_diario.pdf',
                    customize: function (doc) {
                        doc.content[1].table.widths = ['5%', '15%', '15%', '15%', '15%', '8%', '8%', '8%'];
                        doc.defaultStyle.fontSize = 9;
                    }
                },
                { 
                    extend: 'excel', 
                    className: 'btn yellow btn-outline ',
                    filename: 'reporte_diario.xlsx'
                },
                { 
                    extend: 'csv', 
                    className: 'btn purple btn-outline ',
                    filename: 'reporte_diario.csv'
                },
                { extend: 'colvis', className: 'btn dark btn-outline', text: 'Columns'}
            ],

            responsive: true,
            "order": [[0, 'asc']],
            
            "lengthMenu": [
                [5, 10, 15, 20, -1],
                [5, 10, 15, 20, "All"]
            ],
            "pageLength": 10,

            "dom": "<'row' <'col-md-12'B>><'row'<'col-md-6 col-sm-12'l><'col-md-6 col-sm-12'f>r><'table-scrollable't><'row'<'col-md-5 col-sm-12'i><'col-md-7 col-sm-12'p>>"
        });
    }

    var initTable2 = function () {
        var table = $('#sample_2');
        if (!table.length) return;

        var oTable = table.dataTable({

            "language": {
                "aria": {
                    "sortAscending": ": activate to sort column ascending",
                    "sortDescending": ": activate to sort column descending"
                },
                "emptyTable": "No data available in table",
                "info": "Showing _START_ to _END_ of _TOTAL_ entries",
                "infoEmpty": "No entries found",
                "infoFiltered": "(filtered from _MAX_ total entries)",
                "lengthMenu": "_MENU_ entries",
                "search": "Search:",
                "zeroRecords": "No matching records found"
            },

            buttons: [
                { extend: 'copy', className: 'btn default' },
                { 
                    extend: 'pdf', 
                    className: 'btn default',
                    exportOptions: {
                        modifier: {
                            search: 'none',
                            order: 'current',
                            page: 'all'
                        }
                    },
                    orientation: 'landscape',
                    pageSize: 'A4',
                    filename: 'reporte_mensual.pdf',
                    customize: function (doc) {
                        doc.content[1].table.widths = ['5%', '15%', '15%', '15%', '15%', '8%', '8%', '8%'];
                        doc.defaultStyle.fontSize = 9;
                    }
                },
                { 
                    extend: 'excel', 
                    className: 'btn default',
                    filename: 'reporte_mensual.xlsx'
                },
                { 
                    extend: 'csv', 
                    className: 'btn default',
                    filename: 'reporte_mensual.csv'
                },
                {
                    text: 'Reload',
                    className: 'btn default',
                    action: function ( e, dt, node, config ) {
                        oTable.DataTable().draw(false);
                    }
                }
            ],

            "order": [[0, 'asc']],
            
            "lengthMenu": [
                [5, 10, 15, 20, -1],
                [5, 10, 15, 20, "All"]
            ],
            "pageLength": 10,

            "dom": "<'row' <'col-md-12'B>><'row'<'col-md-6 col-sm-12'l><'col-md-6 col-sm-12'f>r><'table-scrollable't><'row'<'col-md-5 col-sm-12'i><'col-md-7 col-sm-12'p>>"
        });
    }

    var initTable3 = function () {
        var table = $('#sample_3');
        if (!table.length) return;

        var oTable = table.dataTable({

            "language": {
                "aria": {
                    "sortAscending": ": activate to sort column ascending",
                    "sortDescending": ": activate to sort column descending"
                },
                "emptyTable": "No data available in table",
                "info": "Showing _START_ to _END_ of _TOTAL_ entries",
                "infoEmpty": "No entries found",
                "infoFiltered": "(filtered from _MAX_ total entries)",
                "lengthMenu": "_MENU_ entries",
                "search": "Search:",
                "zeroRecords": "No matching records found"
            },

            buttons: [
                { extend: 'copy', className: 'btn red btn-outline' },
                { 
                    extend: 'pdf', 
                    className: 'btn green btn-outline',
                    exportOptions: {
                        modifier: {
                            search: 'none',
                            order: 'current',
                            page: 'all'
                        }
                    },
                    orientation: 'landscape',
                    pageSize: 'A4',
                    filename: 'reporte_detalles.pdf',
                    customize: function (doc) {
                        doc.content[1].table.widths = ['5%', '20%', '20%', '15%', '15%', '10%', '8%', '7%'];
                        doc.defaultStyle.fontSize = 8;
                    }
                },
                { 
                    extend: 'excel', 
                    className: 'btn yellow btn-outline ',
                    filename: 'reporte_detalles.xlsx'
                },
                { 
                    extend: 'csv', 
                    className: 'btn purple btn-outline ',
                    filename: 'reporte_detalles.csv'
                },
                { extend: 'colvis', className: 'btn dark btn-outline', text: 'Columns'}
            ],

            responsive: false,
            "order": [[0, 'desc']],
            
            "lengthMenu": [
                [5, 10, 15, 20, -1],
                [5, 10, 15, 20, "All"]
            ],
            "pageLength": 10
        });

        $('#sample_3_tools > li > a.tool-action').on('click', function() {
            var action = $(this).attr('data-action');
            oTable.DataTable().button(action).trigger();
        });
    }
	
	var initTable4 = function () {
        var table = $('#metro_tpl_2');
        if (!table.length) return;

        var oTable = table.dataTable({

            "language": {
                "aria": {
                    "sortAscending": ": activate to sort column ascending",
                    "sortDescending": ": activate to sort column descending"
                },
                "emptyTable": "No data available in table",
                "info": "Showing _START_ to _END_ of _TOTAL_ entries",
                "infoEmpty": "No entries found",
                "infoFiltered": "(filtered from _MAX_ total entries)",
                "lengthMenu": "_MENU_ entries",
                "search": "Search:",
                "zeroRecords": "No matching records found"
            },

            buttons: [
                { extend: 'copy', className: 'btn red btn-outline' },
                { 
                    extend: 'pdf', 
                    className: 'btn green btn-outline',
                    exportOptions: {
                        modifier: {
                            search: 'none',
                            order: 'current',
                            page: 'all'
                        }
                    },
                    orientation: 'landscape',
                    pageSize: 'A4',
                    filename: 'reporte_metro.pdf',
                    customize: function (doc) {
                        doc.content[1].table.widths = ['5%', '20%', '20%', '15%', '15%', '10%', '8%', '7%'];
                        doc.defaultStyle.fontSize = 8;
                    }
                },
                { 
                    extend: 'excel', 
                    className: 'btn yellow btn-outline ',
                    filename: 'reporte_metro.xlsx'
                },
                { 
                    extend: 'csv', 
                    className: 'btn purple btn-outline ',
                    filename: 'reporte_metro.csv'
                },
                { extend: 'colvis', className: 'btn dark btn-outline', text: 'Columns'}
            ],

            responsive: false,
            "order": [[0, 'asc']],
            
            "lengthMenu": [
                [5, 10, 15, 20, -1],
                [5, 10, 15, 20, "All"]
            ],
            "pageLength": 10
        });

        $('#sample_3_tools > li > a.tool-action').on('click', function() {
            var action = $(this).attr('data-action');
            oTable.DataTable().button(action).trigger();
        });
    }

	var initTable5 = function () {
        var table = $('#metro_tpl_3');
        if (!table.length) return;

        var oTable = table.dataTable({

            "language": {
                "aria": {
                    "sortAscending": ": activate to sort column ascending",
                    "sortDescending": ": activate to sort column descending"
                },
                "emptyTable": "No data available in table",
                "info": "Showing _START_ to _END_ of _TOTAL_ entries",
                "infoEmpty": "No entries found",
                "infoFiltered": "(filtered from _MAX_ total entries)",
                "lengthMenu": "_MENU_ entries",
                "search": "Search:",
                "zeroRecords": "No matching records found"
            },

            buttons: [
                { extend: 'copy', className: 'btn red btn-outline' },
                { 
                    extend: 'pdf', 
                    className: 'btn green btn-outline',
                    exportOptions: {
                        modifier: {
                            search: 'none',
                            order: 'current',
                            page: 'all'
                        }
                    },
                    orientation: 'landscape',
                    pageSize: 'A4',
                    filename: 'reporte_metro_3.pdf'
                },
                { 
                    extend: 'excel', 
                    className: 'btn yellow btn-outline ',
                    filename: 'reporte_metro_3.xlsx'
                },
                { 
                    extend: 'csv', 
                    className: 'btn purple btn-outline ',
                    filename: 'reporte_metro_3.csv'
                },
                { extend: 'colvis', className: 'btn dark btn-outline', text: 'Columns'}
            ],

            responsive: false,
            "order": false,
            
            "lengthMenu": [
                [5, 10, 15, 20, -1],
                [5, 10, 15, 20, "All"]
            ],
            "pageLength": 10
        });

        $('#metro_tpl_3_tools > li > a.tool-action').on('click', function() {
            var action = $(this).attr('data-action');
            oTable.DataTable().button(action).trigger();
        });
    }

    var initAjaxDatatables = function () {
        if (!$('#datatable_ajax').length) return;

        $('.date-picker').datepicker({
            rtl: App.isRTL(),
            autoclose: true
        });

        var grid = new Datatable();

        grid.init({
            src: $("#datatable_ajax"),
            onSuccess: function (grid, response) {
                // grid:        grid object
                // response:    json object of server side ajax response
            },
            onError: function (grid) {
                // execute some code on network or other general error  
            },
            onDataLoad: function(grid) {
                // execute some code on ajax data load
            },
            loadingMessage: 'Loading...',
            dataTable: {
                
                "bStateSave": true,

                "lengthMenu": [
                    [10, 20, 50, 100, 150, -1],
                    [10, 20, 50, 100, 150, "All"]
                ],
                "pageLength": 10,
                "ajax": {
                    "url": "../demo/table_ajax.php",
                },
                "order": [
                    [1, "asc"]
                ],

                buttons: [
                    { extend: 'copy', className: 'btn default' },
                    { 
                        extend: 'pdf', 
                        className: 'btn default',
                        exportOptions: {
                            modifier: {
                                search: 'none',
                                order: 'current',
                                page: 'all'
                            }
                        },
                        orientation: 'landscape',
                        pageSize: 'A4',
                        filename: 'reporte_ajax.pdf'
                    },
                    { 
                        extend: 'excel', 
                        className: 'btn default',
                        filename: 'reporte_ajax.xlsx'
                    },
                    { 
                        extend: 'csv', 
                        className: 'btn default',
                        filename: 'reporte_ajax.csv'
                    },
                    {
                        text: 'Reload',
                        className: 'btn default',
                        action: function ( e, dt, node, config ) {
                            dt.ajax.reload();
                        }
                    }
                ],

            }
        });

        grid.getTableWrapper().on('click', '.table-group-action-submit', function (e) {
            e.preventDefault();
            var action = $(".table-group-action-input", grid.getTableWrapper());
            if (action.val() != "" && grid.getSelectedRowsCount() > 0) {
                grid.setAjaxParam("customActionType", "group_action");
                grid.setAjaxParam("customActionName", action.val());
                grid.setAjaxParam("id", grid.getSelectedRows());
                grid.getDataTable().ajax.reload();
                grid.clearAjaxParams();
            } else if (action.val() == "") {
                App.alert({
                    type: 'danger',
                    icon: 'warning',
                    message: 'Please select an action',
                    container: grid.getTableWrapper(),
                    place: 'prepend'
                });
            } else if (grid.getSelectedRowsCount() === 0) {
                App.alert({
                    type: 'danger',
                    icon: 'warning',
                    message: 'No record selected',
                    container: grid.getTableWrapper(),
                    place: 'prepend'
                });
            }
        });

        $('#datatable_ajax_tools > li > a.tool-action').on('click', function() {
            var action = $(this).attr('data-action');
            grid.getDataTable().button(action).trigger();
        });
    }

    return {

        init: function () {

            if (!jQuery().dataTable) {
                return;
            }

            initTable1();
            initTable2();
            initTable3();
			initTable4();
			initTable5();

            initAjaxDatatables();
        }

    };

}();

jQuery(document).ready(function() {
    TableDatatablesButtons.init();
});
