<script>
window.embeddedChatbotConfig = {
chatbotId: "66L4HhM44XkXmxvvDzQec",
domain: "www.chatbase.co"
}
</script>
<script
src="https://www.chatbase.co/embed.min.js"
chatbotId="66L4HhM44XkXmxvvDzQec"
domain="www.chatbase.co"
defer>
</script>



<?php
session_start();
include("connect.php");

// Check if the user is logged in
if (!isset($_SESSION['user_id'])) {
    // Redirect to login if not logged in
    header("Location: login.php");
    exit();
}

// Debugging: Check if username is set
$username = isset($_SESSION['first_name']) ? $_SESSION['first_name'] : 'Guest';

// Fetch user details (annual income, email) from 'registered' table
$user_id = $_SESSION['user_id'];
$query = "SELECT yearly_revenue, company_name,company_id, cost FROM business WHERE user_id = ?";
$stmt = $conn->prepare($query);
$stmt->bind_param("i", $user_id); // Assuming user_id is an integer
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    // Fetch the user's data
    $user_data = $result->fetch_assoc();
    $yearly_revenue = $user_data['yearly_revenue'];
    $company_name = $user_data['company_name'];
    $company_id = $user_data['company_id'];
    $cost = $user_data['cost'];
} else {
    // Handle the case where no user is found
    $yearly_revenue = 'N/A';
    $company_name = 'N/A';
    $cost = 'N/A';
}

// Calculate monthly income
if (is_numeric($yearly_revenue) && $yearly_revenue > 0) {
    $monthly_revenue = $yearly_revenue / 12;
    $monthly_revenue = number_format($monthly_revenue, 2);
} else {
    $monthly_revenue = '0.00'; // Default to 0 if income is not valid
}
if (is_numeric($yearly_revenue) && $yearly_revenue > 0){
  if (is_numeric($cost) && $cost > 0){
    $profit = $yearly_revenue - $cost;
    $profit = number_format($profit, 2);
  }else {
    $profit = '0.00'; // Default to 0 if income is not valid
}
}else {
  $profit = '0.00'; // Default to 0 if income is not valid
}

// Query to get the total payments from all tables
// $query = "
//     SELECT 
//         (SELECT IFNULL(SUM(paying_amount), 0) FROM payment_incometax WHERE user_id = ?) AS total_income_paid,
//         (SELECT IFNULL(SUM(paying_amount), 0) FROM payment_land WHERE user_id = ?) AS total_land_paid,
//         (SELECT IFNULL(SUM(paying_amount), 0) FROM payment_vehicle WHERE user_id = ?) AS total_vehicle_paid
// ";
// $stmt2 = $conn->prepare($query);
// $stmt2->bind_param("i", $user_id); // Bind the user_id 3 times for each subquery
// $stmt2->execute();
// $result2 = $stmt2->get_result();

// if ($result2->num_rows > 0) {
//     $data = $result2->fetch_assoc();
//     $total_income_paid = $data['total_income_paid'];
//     $total_land_paid = $data['total_land_paid'];
//     $total_vehicle_paid = $data['total_vehicle_paid'];

//     // Calculate the grand total
//     $total_paid = $total_income_paid + $total_land_paid + $total_vehicle_paid;
// } else {
//     $total_income_paid = 0;
//     $total_land_paid = 0;
//     $total_vehicle_paid = 0;
//     $total_paid = 0;
// }

?>
<?php


// Prepare monthly payment data
$months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
$total_income = array_fill(0, 12, 0);
$total_land = array_fill(0, 12, 0);
$total_vehicle = array_fill(0, 12, 0);


$query_income = "
    SELECT MONTH(paying_date) as month, IFNULL(SUM(paying_amount), 0) AS total_income
    FROM payment_incometax
    WHERE user_id = '$user_id' AND paying_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY MONTH(paying_date)
";
$result_income = mysqli_query($conn, $query_income);
while ($row = $result_income->fetch_assoc()) {
    $total_income[$row['month'] - 1] = $row['total_income']; // Store income totals
}

// Fetch payment data from payment_land
$query_land = "
    SELECT MONTH(paying_date) as month, IFNULL(SUM(paying_amount), 0) AS total_land
    FROM payment_land
    WHERE user_id = '$user_id' AND paying_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY MONTH(paying_date)
";
$result_land = mysqli_query($conn, $query_land);
while ($row = $result_land->fetch_assoc()) {
    $total_land[$row['month'] - 1] = $row['total_land']; // Store land totals
}

// Fetch payment data from payment_vehicle
$query_vehicle = "
    SELECT MONTH(paying_date) as month, IFNULL(SUM(paying_amount), 0) AS total_vehicle
    FROM payment_vehicle
    WHERE user_id = '$user_id' AND paying_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY MONTH(paying_date)
";
$result_vehicle = mysqli_query($conn, $query_vehicle);
while ($row = $result_vehicle->fetch_assoc()) {
    $total_vehicle[$row['month'] - 1] = $row['total_vehicle']; // Store vehicle totals
}


?>



<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
  <link rel="apple-touch-icon" sizes="76x76" href="./assets/img/apple-icon.png">
  <link rel="icon" type="image/png" href="./assets/img/favicon.png">
  <title>
    TaxEase
  </title>
  <!--     Fonts and icons     -->
  <link href="https://fonts.googleapis.com/css?family=Open+Sans:300,400,600,700" rel="stylesheet" />
  <!-- Nucleo Icons -->
  <link href="./assets/css/nucleo-icons.css" rel="stylesheet" />
  <link href="./assets/css/nucleo-svg.css" rel="stylesheet" />
  <!-- Font Awesome Icons -->
  <script src="https://kit.fontawesome.com/42d5adcbca.js" crossorigin="anonymous"></script>
  <link href="./assets/css/nucleo-svg.css" rel="stylesheet" />
  <!-- CSS Files -->
  <link id="pagestyle" href="./assets/css/argon-dashboard.css?v=2.0.4" rel="stylesheet" />
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
        .btn-black {
            background-color: #000; /* Black background */
            color: #fff; /* White text */
            border: none; /* Remove border */
            padding: 15px 30px; /* Padding for larger button */
            font-size: 16px; /* Font size */
            font-weight: bold; /* Bold text */
            text-decoration: none; /* Remove underline */
            border-radius: 5px; /* Rounded corners */
            transition: background-color 0.3s ease; /* Smooth transition for hover */
            display: inline-block; /* Block element for padding */
        }

        .btn-black:hover {
            background-color: #444; /* Darker shade on hover */
        }
    </style>
</head>

<body class="g-sidenav-show   bg-gray-100">
  <div class="min-height-300 bg-primary position-absolute w-100"></div>
  <aside class="sidenav bg-white navbar navbar-vertical navbar-expand-xs border-0 border-radius-xl my-3 fixed-start ms-4 " id="sidenav-main">
    <div class="sidenav-header">
      <i class="fas fa-times p-3 cursor-pointer text-secondary opacity-5 position-absolute end-0 top-0 d-none d-xl-none" aria-hidden="true" id="iconSidenav"></i>
      <a class="navbar-brand m-0" href=" dashboard2.php " target="_blank">
        <img src="./assets/img/logo-ct-dark.png" class="navbar-brand-img h-100" alt="main_logo">
        <span class="ms-1 font-weight-bold">TaxEase</span>
      </a>
    </div>
    <hr class="horizontal dark mt-0">
    <div class="collapse navbar-collapse  w-auto " id="sidenav-collapse-main">
      <ul class="navbar-nav">
      <li class="nav-item mt-3">
        <h6 class="ps-4 ms-2 text-uppercase text-sm font-weight-bolder opacity-6">User Details</h6>
      </li>
      <li class="nav-item">
          <div class="ps-4 ms-2">
              <p class="text-sm mb-0" style="color: black; font-weight: bold;">Company Name: <?php echo htmlspecialchars($company_name); ?></p>
              <p class="text-sm mb-0" style="color: black; font-weight: bold;">ID: <?php echo htmlspecialchars($company_id); ?></p>
          </div>
      </li>
        <li class="nav-item">
          <a class="nav-link active" href="businessdashboard.php">
            <div class="icon icon-shape icon-sm border-radius-md text-center me-2 d-flex align-items-center justify-content-center">
              <i class="ni ni-tv-2 text-primary text-sm opacity-10"></i>
            </div>
            <span class="nav-link-text ms-1">Dashboard</span>
          </a>
        </li>
        
        
        <li class="nav-item">
          <a class="nav-link " href="ForBusiness.php">
            <div class="icon icon-shape icon-sm border-radius-md text-center me-2 d-flex align-items-center justify-content-center">
              <i class="ni ni-credit-card text-success text-sm opacity-10"></i>
            </div>
            <span class="nav-link-text ms-1">Busines Pay</span>
          </a>
        </li>
        <li class="nav-item">
          <a class="nav-link" href="faq.php">
            <div class="icon icon-shape icon-sm border-radius-md text-center me-2 d-flex align-items-center justify-content-center">
              
              <i class="ni ni-support-16 text-info text-sm opacity-10"></i> 
            </div>
            <span class="nav-link-text ms-1">FAQ</span> 
          </a>
      </li>
      <li class="nav-item">
          <a class="nav-link" href="edit_businessprofile.php">
            <div class="icon icon-shape icon-sm border-radius-md text-center me-2 d-flex align-items-center justify-content-center">
              
              <i class="ni ni-support-16 text-info text-sm opacity-10"></i> 
            </div>
            <span class="nav-link-text ms-1">Edit profile</span> 
          </a>
      </li>
        

      </ul>
    </div>
    
  </aside>
  <main class="main-content position-relative border-radius-lg ">
    <!-- Navbar -->
    <nav class="navbar navbar-main navbar-expand-lg px-0 mx-4 shadow-none border-radius-xl " id="navbarBlur" data-scroll="false">
      <div class="container-fluid py-1 px-3">
        <nav aria-label="breadcrumb">
          <ol class="breadcrumb bg-transparent mb-0 pb-0 pt-1 px-0 me-sm-6 me-5">
            <li class="breadcrumb-item text-sm"><a class="opacity-5 text-white" href="javascript:;">Pages</a></li>
            <li class="breadcrumb-item text-sm text-white active" aria-current="page">Dashboard</li>
          </ol>
          <h6 class="font-weight-bolder text-white mb-0">Dashboard</h6>
          <div>
            
          </div>
        </nav>

        <div class="collapse navbar-collapse mt-sm-0 mt-2 me-md-0 me-sm-4" id="navbar">
        
        <div class="ms-md-auto pe-md-3 d-flex align-items-center">
        <div class="input-group me-3"> <!-- Added margin end (me-3) -->
            <span class="input-group-text text-body"><i class="fas fa-search" aria-hidden="true"></i></span>
            <input type="text" class="form-control" placeholder="Type here...">
        </div>
    </div>
          <ul class="navbar-nav  justify-content-end">
            <li class="nav-item d-flex align-items-center">
              <a href="javascript:;" class="nav-link text-white font-weight-bold px-0">
                <i class="fa fa-user me-sm-1"></i>
                <span class="d-sm-inline d-none"><?php echo htmlspecialchars($company_name); ?></span>
              </a>
            </li>
            
            
        
            <li class="nav-item d-flex align-items-center" style="margin-left: 20px;"> <!-- Added margin here -->
                <a href="logout.php" class="nav-link text-white font-weight-bold px-0">
                    <span class="ms-1 d-sm-inline d-none">Logout</span>
                </a>
            </li>

            <li class="nav-item d-flex align-items-center" style="margin-left: 20px;"> <!-- Added margin here -->
                <a href="dashboard2.php" class="nav-link text-white font-weight-bold px-0">
                    <span class="ms-1 d-sm-inline d-none">Back to user profile</span>
                </a>
            </li>


          </ul>
        </div>
      </div>
    </nav>
    <!-- End Navbar -->
    <div class="container-fluid py-4">
      <div class="row">
        <div class="col-xl-3 col-sm-6 mb-xl-0 mb-4">
          <div class="card">
            <div class="card-body p-3">
              <div class="row">
                <div class="col-8">
                  <div class="numbers">
                    <p class="text-sm mb-0 text-uppercase font-weight-bold">Monthly Income</p>
                    <h5 class="font-weight-bolder">TK
                    <?php echo htmlspecialchars($monthly_revenue); ?>
                    </h5>
                  </div>
                </div>
                <div class="col-4 text-end">
                  <div class="icon icon-shape bg-gradient-primary shadow-primary text-center rounded-circle">
                    <i class="ni ni-money-coins text-lg opacity-10" aria-hidden="true"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="col-xl-3 col-sm-6 mb-xl-0 mb-4">
          <div class="card">
            <div class="card-body p-3">
              <div class="row">
                <div class="col-8">
                  <div class="numbers">
                    <p class="text-sm mb-0 text-uppercase font-weight-bold">Yearly Income</p>
                    <h5 class="font-weight-bolder"> TK
                    <?php echo htmlspecialchars($yearly_revenue); ?>
                    </h5>
                  </div>
                </div>
                <div class="col-4 text-end">
                  <div class="icon icon-shape bg-gradient-danger shadow-danger text-center rounded-circle">
                    <i class="ni ni-world text-lg opacity-10" aria-hidden="true"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="col-xl-3 col-sm-6 mb-xl-0 mb-4">
          <div class="card">
            <div class="card-body p-3">
              <div class="row">
                <div class="col-8">
                  <div class="numbers">
                    <p class="text-sm mb-0 text-uppercase font-weight-bold">Cost</p>
                    <h5 class="font-weight-bolder">
                    <?php echo htmlspecialchars($cost); ?>
                    </h5>
                    <!-- <p class="mb-0">
                      <span class="text-danger text-sm font-weight-bolder">-2%</span>
                      since last quarter
                    </p> -->
                  </div>
                </div>
                <div class="col-4 text-end">
                  <div class="icon icon-shape bg-gradient-success shadow-success text-center rounded-circle">
                    <i class="ni ni-paper-diploma text-lg opacity-10" aria-hidden="true"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="col-xl-3 col-sm-6">
          <div class="card">
            <div class="card-body p-3">
              <div class="row">
                <div class="col-8">
                  <div class="numbers">
                    <p class="text-sm mb-0 text-uppercase font-weight-bold">Profit</p>
                    <h5 class="font-weight-bolder"> TK
                    <?php echo htmlspecialchars($profit); ?>
                    </h5>
                  </div>
                </div>
                <div class="col-4 text-end">
                  <div class="icon icon-shape bg-gradient-warning shadow-warning text-center rounded-circle">
                    <i class="ni ni-cart text-lg opacity-10" aria-hidden="true"></i>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="row mt-4">
        <div class="col-lg-7 mb-lg-0 mb-4">
          <div class="card z-index-2 h-100">
            <div class="card-header pb-0 pt-3 bg-transparent">
              <h6 class="text-capitalize">Tax Overview</h6>
            </div>
            <div class="card-body p-3">
            <div class="chart">
              <canvas id="chart-line" class="chart-canvas" height="300"></canvas>
            </div>


            </div>
          </div>
        </div>
        <div class="col-lg-5">
          <div class="card card-carousel overflow-hidden h-100 p-0">
            <div id="carouselExampleCaptions" class="carousel slide h-100" data-bs-ride="carousel">
              <div class="carousel-inner border-radius-lg h-100">
                <div class="carousel-item h-100 active" style="background-image: url('./assets/img/carousel-1.jpg');
      background-size: cover;">
                  <div class="carousel-caption d-none d-md-block bottom-0 text-start start-0 ms-5">
                    <div class="icon icon-shape icon-sm bg-white text-center border-radius-md mb-3">
                      <i class="ni ni-camera-compact text-dark opacity-10"></i>
                    </div>
                    <h5 class="text-white mb-1">Is it safe?</h5>
                    <p>Yes, our platform uses advanced security measures to protect your transactions and personal data, for more information contact us, via e-mail</p>
                  </div>
                </div>
                <div class="carousel-item h-100" style="background-image: url('./assets/img/carousel-2.jpg');
      background-size: cover;">
                  <div class="carousel-caption d-none d-md-block bottom-0 text-start start-0 ms-5">
                    <div class="icon icon-shape icon-sm bg-white text-center border-radius-md mb-3">
                      <i class="ni ni-bulb-61 text-dark opacity-10"></i>
                    </div>
                    <h5 class="text-white mb-1">Faster way to create web pages</h5>
                    <p>That’s my skill. I’m not really specifically talented at anything except for the ability to learn.</p>
                  </div>
                </div>
                <div class="carousel-item h-100" style="background-image: url('./assets/img/carousel-3.jpg');
      background-size: cover;">
                  <div class="carousel-caption d-none d-md-block bottom-0 text-start start-0 ms-5">
                    <div class="icon icon-shape icon-sm bg-white text-center border-radius-md mb-3">
                      <i class="ni ni-trophy text-dark opacity-10"></i>
                    </div>
                    <h5 class="text-white mb-1">Why TaxEase?</h5>
                    <p>TaxEase offers secure, fast, and easy payment processing with transparent pricing and strong data protection, making it a reliable choice for individuals and businesses alike</p>
                  </div>
                </div>
              </div>
              <button class="carousel-control-prev w-5 me-3" type="button" data-bs-target="#carouselExampleCaptions" data-bs-slide="prev">
                <span class="carousel-control-prev-icon" aria-hidden="true"></span>
                <span class="visually-hidden">Previous</span>
              </button>
              <button class="carousel-control-next w-5 me-3" type="button" data-bs-target="#carouselExampleCaptions" data-bs-slide="next">
                <span class="carousel-control-next-icon" aria-hidden="true"></span>
                <span class="visually-hidden">Next</span>
              </button>
            </div>
          </div>
        </div>
      </div>
      <div class="row mt-4">
        <div class="col-lg-7 mb-lg-0 mb-4">
          <div class="card ">
            <div class="card-header pb-0 p-3">
              <div class="d-flex justify-content-between">
                <h6 class="mb-2">Payment History</h6>
              </div>
            </div>
            <div class="table-responsive">
              <table class="table align-items-center ">
                <tbody>
                <?php


                // Query to fetch payment history from all three tables
                $query = "
                    SELECT 'Business Tax' AS paying_date, paying_amount 
                    FROM business_payment 
                    WHERE user_id = '$user_id'
                    
                ";

                $result = mysqli_query($conn, $query);

                // Check if any payments were found
                if ($result->num_rows > 0) {
                    echo '<table class="table align-items-center text-center">';
                    echo '<thead><tr><th>Payment date</th><th>Paying Amount</th></tr></thead>';
                    echo '<tbody>';

                    // Loop through the results and display each payment record
                    while ($row = $result->fetch_assoc()) {
                        echo '<tr>';
                        echo '<td>' . htmlspecialchars(date('Y-m-d', strtotime($row['paying_date']))) . '</td>';
                        echo '<td>' . htmlspecialchars(number_format($row['paying_amount'], 2)) . '</td>';
                       
                        echo '</tr>';
                    }

                    echo '</tbody>';
                    echo '</table>';
                } else {
                    echo 'No payment history found.';
                }
                ?>

              </table>
            </div>
          </div>
        </div>
       
        <div class="col-lg-5">
    <div class="card">
        <div class="card-header pb-0 p-3">
            <h6 class="mb-0">Calculator</h6>
        </div>
        <div class="d-flex justify-content-center align-items-center" style="height: 200px;"> <!-- Centering container -->
            <a href="businesscalcu.php" class="btn btn-black">Calculate Your business Tax</a>
        </div>
    </div>  
</div>
  
                  
      
  <!--   Core JS Files   -->
  <script src="./assets/js/core/popper.min.js"></script>
  <script src="./assets/js/core/bootstrap.min.js"></script>
  <script src="./assets/js/plugins/perfect-scrollbar.min.js"></script>
  <script src="./assets/js/plugins/smooth-scrollbar.min.js"></script>
  <script src="./assets/js/plugins/chartjs.min.js"></script>
        <script>
            var ctx1 = document.getElementById("chart-line").getContext("2d");

            var gradientStroke1 = ctx1.createLinearGradient(0, 230, 0, 50);
            gradientStroke1.addColorStop(1, 'rgba(94, 114, 228, 0.2)');
            gradientStroke1.addColorStop(0.2, 'rgba(94, 114, 228, 0.0)');
            gradientStroke1.addColorStop(0, 'rgba(94, 114, 228, 0)');

            new Chart(ctx1, {
                type: "line",
                data: {
        labels: <?php echo json_encode($months); ?>,
        datasets: [
            {
                label: "Income Tax",
                tension: 0.4,
                borderWidth: 0,
                pointRadius: 0,
                borderColor: "#5e72e4",  // Blue color for Income Tax
                backgroundColor: gradientStroke1,
                borderWidth: 3,
                fill: true,
                data: <?php echo json_encode($total_income); ?>,
            },
            {
                label: "Land Payments",
                tension: 0.4,
                borderWidth: 0,
                pointRadius: 0,
                borderColor: "#FF6384",  // Pink color for Land Payments
                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                borderWidth: 3,
                fill: true,
                data: <?php echo json_encode($total_land); ?>,
            },
            {
                label: "Vehicle Payments",
                tension: 0.4,
                borderWidth: 0,
                pointRadius: 0,
                borderColor: "#28A745",  // Green color for Vehicle Payments
                backgroundColor: 'rgba(40, 167, 69, 0.2)', // Light green background
                borderWidth: 3,
                fill: true,
                data: <?php echo json_encode($total_vehicle); ?>,
            }
        ],
    },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: true,
                        }
                    },
                    interaction: {
                        intersect: false,
                        mode: 'index',
                    },
                    scales: {
                        y: {
                            grid: {
                                drawBorder: false,
                                display: true,
                                drawOnChartArea: true,
                                drawTicks: false,
                                borderDash: [5, 5]
                            },
                            ticks: {
                                display: true,
                                padding: 10,
                                color: '#fbfbfb',
                                font: {
                                    size: 11,
                                    family: "Open Sans",
                                    style: 'normal',
                                    lineHeight: 2
                                },
                            }
                        },
                        x: {
                            grid: {
                                drawBorder: false,
                                display: false,
                                drawOnChartArea: false,
                                drawTicks: false,
                                borderDash: [5, 5]
                            },
                            ticks: {
                                display: true,
                                color: '#ccc',
                                padding: 20,
                                font: {
                                    size: 11,
                                    family: "Open Sans",
                                    style: 'normal',
                                    lineHeight: 2
                                },
                            }
                        },
                    },
                },
            });
        </script>

  
  <script>
    var win = navigator.platform.indexOf('Win') > -1;
    if (win && document.querySelector('#sidenav-scrollbar')) {
      var options = {
        damping: '0.5'
      }
      Scrollbar.init(document.querySelector('#sidenav-scrollbar'), options);
    }
  </script>
  <!-- Github buttons -->
  <script async defer src="https://buttons.github.io/buttons.js"></script>
  <!-- Control Center for Soft Dashboard: parallax effects, scripts for the example pages etc -->
  <script src="./assets/js/argon-dashboard.min.js?v=2.0.4"></script>
</body>

</html>